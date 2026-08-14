# NetBird — self-hosted WireGuard mesh + reverse proxy. Replaces Pangolin.
#
# Two aspects, mirroring the pangolin.nix layout they supersede:
#
#   services.netbird.client  the mesh client (every host). Also owns the
#                            options shared with the server.
#   services.netbird         the control plane (gaia): management, signal,
#                            dashboard and coturn from nixpkgs, plus the
#                            reverse proxy and its service provisioning, which
#                            nixpkgs has no module for. Includes the client, so
#                            gaia is a peer like everything else.
#
# Why this replaced Pangolin: newt/pangolin only ever tunnelled *inbound*
# traffic to gaia, so the hosts could not address each other and a roaming
# voyager could reach nothing. A mesh solves that directly, and NetBird's
# reverse proxy covers the ingress half Pangolin was also doing.
#
# Port 443 on gaia is shared by two things that both need to own a TLS
# handshake: the control-plane vhost, and the reverse proxy (which runs its own
# ACME). nginx `ssl_preread` splits them by SNI without decrypting either —
# NetBird's docs mandate Traefik here, but this is precisely what ssl_preread
# is for, and it keeps gaia on the nginx the dashboard already needs.
{den, ...}: {
  # Mesh client. Every host runs this; it is what makes them addressable by
  # name from anywhere, which is the whole point of the migration.
  den.aspects.services.netbird.client.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) enum ints listOf port str;

    cfg = config.cosmos.services.netbird;

    # See the long comment at the unit for what this is defending against.
    aclWatchdog = pkgs.writeShellApplication {
      name = "netbird-acl-watchdog";
      runtimeInputs = with pkgs; [nftables systemd gnugrep];
      text = ''
        chain="netbird-acl-input-rules"

        # If the table is absent entirely the agent is not up yet — starting,
        # stopped, or mid-restart. That is not the decay this is looking for,
        # and restarting into it would just fight whatever is already
        # happening.
        if ! rules="$(nft list chain ip netbird "$chain" 2>/dev/null)"; then
          echo "netbird-acl-watchdog: no $chain yet, nothing to judge"
          exit 0
        fi

        # The chain is legitimately incomplete for a few seconds after the agent
        # starts, while it re-syncs policy from management. Restarting into that
        # window would fight the startup it is watching — and because the remedy
        # here *is* a restart, doing so could loop. Anything under the grace
        # period is left alone; the timer comes back shortly.
        active_us="$(systemctl show ${config.services.netbird.clients.default.suffixedName}.service \
          -p ActiveEnterTimestampMonotonic --value)"
        if [[ -n "$active_us" && "$active_us" != "0" ]]; then
          now_us="$(( $(cut -d' ' -f1 /proc/uptime | tr -d '.') * 10000 ))"
          if (( now_us - active_us < ${toString cfg.client.aclWatchdogGrace} * 1000000 )); then
            echo "netbird-acl-watchdog: agent started under ${toString cfg.client.aclWatchdogGrace}s ago, still converging"
            exit 0
          fi
        fi

        # The two rules the management policy contributes. Per-service rules
        # always carry a dport, so testing for an accept *without* one is what
        # distinguishes "the Default policy is applied" from "only the reverse
        # proxy's rules survived".
        if grep -q 'ct state established,related.*accept' <<<"$rules" \
          && grep -qE 'ip saddr @nb[0-9]+ accept$' <<<"$rules"; then
          exit 0
        fi

        echo "netbird-acl-watchdog: mesh ACLs have decayed to per-service rules only; restarting the agent"
        echo "--- ruleset before restart ---"
        echo "$rules"
        systemctl restart ${config.services.netbird.clients.default.suffixedName}.service
      '';
    };

    # `url.URL` carries no custom JSON marshalling, so netbird's config.json
    # stores it as the expanded Go struct rather than a string. Absent fields
    # unmarshal to their zero values, so scheme and host are enough.
    urlValue = host: {
      Scheme = "https";
      Host = "${host}:${toString cfg.publicPort}";
      Path = "";
    };
  in {
    options.cosmos.services.netbird = {
      domain = mkOption {
        type = str;
        default = "netbird.lvdar.nl";
        description = "Domain of the control plane (dashboard, management, signal).";
      };

      dnsDomain = mkOption {
        type = str;
        default = "nb.lvdar.nl";
        description = "Suffix peers resolve each other under, e.g. endeavour.nb.lvdar.nl.";
      };

      publicPort = mkOption {
        type = port;
        # Every host has to agree on this, and den gives an aspect no way to
        # read another host's config, so it is a shared default rather than a
        # per-host setting.
        default = 443;
        description = ''
          Public port the control plane answers on. Clients embed it in their
          management URL, so server and clients must agree — which is why it
          lives here rather than in the server-only options.

          It was 9443 while Pangolin's traefik still owned :443 on gaia. That
          only ever bought the dashboard and the mesh: netbird-proxy's ACME
          uses tls-alpn-01, which is answerable on 443 alone, so publishing
          services at all requires this value.
        '';
      };

      client = {
        port = mkOption {
          type = port;
          default = 51820;
        };

        routingFeatures = mkOption {
          type = enum ["none" "client" "server" "both"];
          default = "none";
          description = ''
            Set to "server" on a host that should publish a LAN subnet into the
            mesh (endeavour, for 192.168.2.0/24). Enabling it turns on IP
            forwarding, so it stays off unless asked for.
          '';
        };

        dnsResolverAddress = mkOption {
          type = str;
          default = "";
          example = "127.0.0.1:5053";
          description = ''
            Pin the agent's local DNS resolver to this address instead of
            letting it discover one.

            It normally binds an ephemeral port, which is fine when it is also
            the system resolver — it rewrites resolv.conf to point at itself.
            On a host already running a resolver on :53 it cannot do that, so
            mesh names end up being answered by whatever *is* on :53, from
            public DNS, with the edge's address. Pinning the port gives that
            resolver something stable to forward the mesh domain to. See
            cosmos.services.unbound.mesh.
          '';
        };

        exposedPorts = mkOption {
          type = listOf port;
          default = [];
          description = ''
            Ports reachable from the mesh, and only from the mesh — these are
            opened on the netbird interface rather than globally, so an app
            listening on 0.0.0.0 does not become reachable from the LAN as a
            side effect of being published.

            Needed once `cosmos.networking.edgeTerminated` is on, because the
            edge then targets each app's own port instead of a local vhost.

            TCP only. See exposedUdpPorts below for the other half.
          '';
        };

        exposedUdpPorts = mkOption {
          type = listOf port;
          default = [];
          example = "[24454]";
          description = ''
            The same, for UDP.

            Separate rather than a protocol field on exposedPorts because
            almost everything here is TCP and the list reads as a table of
            services; a per-entry protocol would make the common case noisier
            to serve the rare one. The rare one so far is Simple Voice Chat on
            the Minecraft server, which carries audio over its own UDP port
            alongside the game's TCP.
          '';
        };

        aclWatchdog = mkEnableOption "restarting the agent when its mesh ACLs decay" // {default = true;};

        aclWatchdogInterval = mkOption {
          type = str;
          default = "2min";
          description = ''
            How often to check the ACL chain.

            Was 15 minutes on the theory that decay was rare. It is not: on
            2026-08-12 the chain decayed on *every* agent restart — three in one
            afternoon — and each time the mesh was unreachable until this ran.
            Since the check is one `nft list` that touches no network, the
            interval is really just a bound on how long the mesh stays down, so
            it is set to the smallest value that is still obviously free.
          '';
        };

        aclWatchdogGrace = mkOption {
          type = ints.unsigned;
          default = 90;
          description = ''
            Seconds after the agent becomes active during which a decayed chain
            is tolerated rather than acted on.

            The chain is genuinely incomplete for a few seconds at startup while
            policy is fetched from management. Without this grace the tighter
            interval above would catch that window and restart the agent into
            its own startup — and since the remedy is a restart, that could
            loop rather than converge.
          '';
        };
      };
    };

    config = {
      sops.secrets."keys/netbird/setup-key" = {};

      networking.firewall.interfaces.${config.services.netbird.clients.default.interface} = {
        allowedTCPPorts = cfg.client.exposedPorts;
        allowedUDPPorts = cfg.client.exposedUdpPorts;
      };

      # Which OAuth flow the daemon picks when it needs a user token — for
      # `netbird ssh`, which asks the IdP who you are before it dials.
      #
      # NewOAuthFlow only tries PKCE when it believes a browser can be opened,
      # and on Linux it decides that by reading DESKTOP_SESSION and
      # XDG_CURRENT_DESKTOP out of *its own* environment (client/cmd/login.go,
      # isUnixRunningDesktop). The daemon is a system service, so both are
      # empty however graphical the machine is, and it goes straight to the
      # device code flow instead — which management answers with NotFound,
      # because DeviceAuthorizationFlow.Provider is "none" and kanidm does not
      # advertise a device_authorization_endpoint to point it at anyway. The
      # user sees "no SSO provider returned from management", naming the one
      # flow that is configured and working.
      #
      # So tell it the truth about this host: on a machine with a display
      # manager there is a browser to send the login to, and PKCE — which
      # management fills from the discovery document at startup — is the flow
      # that actually works.
      # One block, because a dynamic attribute path cannot be split across
      # several definitions the way a static one can.
      systemd.services.${config.services.netbird.clients.default.suffixedName} = {
        # Move the agent when its resolver address changes. That address lives
        # in config.json, written by a pre-start script, so the unit itself is
        # identical either way and switch-to-configuration would leave the old
        # process running — still holding :53, which is exactly the port
        # unbound is about to want.
        restartTriggers = [cfg.client.dnsResolverAddress];

        environment =
          lib.mkIf config.services.displayManager.enable
          {XDG_CURRENT_DESKTOP = "netbird-has-a-browser";};
      };

      # Watchdog for an agent bug that has now cost two outages, both on gaia,
      # both at ~12 days of uptime.
      #
      # The agent programs its own nftables table (`ip netbird`), whose input
      # path is a jump into netbird-acl-input-rules followed by a catch-all
      # `iifname "wt0" drop`. A healthy ruleset starts with two entries that
      # come from the management policy rather than from any published service:
      #
      #   ct state established,related accept
      #   ip saddr @nb0000001 accept          <- the "All -> All" Default policy
      #
      # Both silently disappear over time. What is left is only the per-service
      # rules the reverse proxy generated, so the host keeps answering the two
      # published ports and drops everything else — ICMP, SSH, Prometheus
      # scrapes. It presents as "the host is up and serving the internet but is
      # not on the mesh", and `netbird status` still cheerfully reports
      # Connected/P2P because the WireGuard session really is fine.
      #
      # The management policy is not at fault: the API returns the Default
      # policy enabled, bidirectional, all protocols, All -> All, throughout.
      # Only the local translation of it rots, and restarting the agent
      # reinstates it immediately. netbird 0.74.3, which is what nixpkgs has.
      #
      # So this restarts the agent when, and only when, the symptom is present.
      # Deliberately not a periodic preemptive restart: that would hide how
      # often this happens, and the journal line below is the only evidence
      # anyone will ever have of the real frequency.
      systemd.services.netbird-acl-watchdog = lib.mkIf cfg.client.aclWatchdog {
        description = "Restart the NetBird agent if its mesh ACLs have decayed";
        # No wantedBy: timer-driven only. A oneshot that fails during
        # activation makes switch-to-configuration fail, which deploy-rs turns
        # into a rollback.
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe aclWatchdog;
        };
      };

      systemd.timers.netbird-acl-watchdog = lib.mkIf cfg.client.aclWatchdog {
        description = "Periodic NetBird mesh ACL check";
        wantedBy = ["timers.target"];
        timerConfig = {
          # The interval is really a bound on how long the mesh stays down after
          # a decay, so it is short — see aclWatchdogInterval for why 15m turned
          # out to be far too generous. OnBootSec is smaller than it was for the
          # same reason: a decay at boot is exactly the case nobody is watching.
          OnBootSec = "90s";
          OnUnitActiveSec = cfg.client.aclWatchdogInterval;
          # No RandomizedDelaySec: there is nothing to spread here — a single
          # nft read on one host — and the jitter only widened the blackout it
          # is supposed to bound.
          Unit = "netbird-acl-watchdog.service";
        };
      };

      cosmos.system.impermanence.persist.directories = [
        {
          # `name = "netbird"` means suffixedName is bare, so the state dir is
          # /var/lib/netbird rather than /var/lib/netbird-<name>.
          directory = "/var/lib/netbird";
          user = "root";
          group = "root";
          mode = "0750";
        }
      ];

      services.netbird = {
        enable = true;
        useRoutingFeatures = cfg.client.routingFeatures;

        clients.default = {
          inherit (cfg.client) port;

          # The peer's half of the SSH switch: it is willing to run NetBird's
          # SSH server if management asks (cosmos.services.netbird.sshPeers on
          # gaia). Current NetBird defaults this on, so this states what is
          # already true rather than changing it — but the config file is
          # rewritten by the agent, and nothing else here would keep it.
          config.ServerSSHAllowed = true;

          # Enrolls unattended with a setup key. Deliberately not the
          # interactive OIDC flow: that would need kanidm reachable *before*
          # the host is on the mesh, and kanidm is published through it.
          # No `systemdDependencies`, despite nixpkgs' own example proposing
          # `sops-install-secrets.service`: that unit does not exist here.
          # sops-nix installs the secrets from the activation script, which
          # stage 2 runs before it execs systemd, so /run/secrets is already
          # populated by the time any unit starts and there is nothing to wait
          # for. Naming it anyway put a `Requires=` on a not-found unit, which
          # made systemd refuse the start job at every boot — silently, since a
          # unit that never starts logs nothing. That is why gaia sat at
          # `NeedsLogin` with a healthy control plane in front of it.
          login = {
            enable = true;
            setupKeyFile = config.sops.secrets."keys/netbird/setup-key".path;
          };

          # The login unit runs a bare `netbird up`, so the self-hosted
          # management URL has to already be in config.json. That is what the
          # module's `config` drop-in is for.
          #
          # Kept a literal attrset: nix merges `config.ServerSSHAllowed` above
          # with this only while both are literals, and an `//` here turns it
          # into an expression and collides.
          config = {
            ManagementURL = urlValue cfg.domain;
            AdminURL = urlValue cfg.domain;
            CustomDNSAddress = cfg.client.dnsResolverAddress;
          };
        };
      };
    };
  };

  den.aspects.services.netbird = {
    includes = with den.aspects.services; [nginx netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkEnableOption;
      inherit (lib.types) attrsOf bool enum listOf nullOr port str submodule;

      cfg = config.cosmos.services.netbird;

      mgmtPort = config.services.netbird.server.management.port;

      # Everything the browser and the peers address the control plane by. Only
      # spells out the port when it is not the default, so the normal case
      # produces ordinary URLs.
      authority =
        "https://${cfg.domain}"
        + lib.optionalString (cfg.publicPort != 443) ":${toString cfg.publicPort}";

      # Every managed service is named with this prefix so the reconciler can
      # safely delete the ones that disappear from nix without ever touching a
      # service created by hand in the dashboard.
      managedPrefix = "nix-";

      target = submodule {
        options = {
          peer = mkOption {
            type = str;
            description = ''
              Name of the NetBird peer to forward to. Resolved to the peer's id
              at activation time — ids are assigned at enrollment, so they
              cannot be known when this is built.
            '';
          };
          port = mkOption {type = port;};
          protocol = mkOption {
            type = enum ["http" "https" "tcp" "udp" "tls"];
            default = "http";
          };
          path = mkOption {
            type = nullOr str;
            default = null;
            description = "Path prefix to match, for path-based routing.";
          };
        };
      };

      service = submodule ({
        name,
        config,
        ...
      }: {
        options = {
          domain = mkOption {
            type = str;
            default = "${name}.${cfg.baseDomain}";
            defaultText = "<name>.\${baseDomain}";
          };
          mode = mkOption {
            type = enum ["http" "tcp" "udp" "tls"];
            default = "http";
            description = ''
              "http" reverse-proxies at L7, which is what a browser wants and
              what gets a certificate and a CrowdSec check. The others are L4
              passthrough for things that do not speak HTTP — a GPS tracker
              opening a socket, say — and need `listenPort` instead of a name,
              since there is no SNI in a raw connection to route on.
            '';
          };

          listenPort = mkOption {
            type = nullOr port;
            default = null;
            description = ''
              Public port the proxy accepts this on, for the L4 modes.

              The domain is still required and must be unique, but it does not
              route anything here: a raw connection carries no hostname, so the
              port alone decides. A client may therefore reach an L4 service on
              any name pointing at the edge, which is how a device configured
              for `traccar.lvdar.nl:5055` lands on a service declared under a
              different name entirely.
            '';
          };
          enabled = mkOption {
            type = bool;
            default = true;
          };

          passHostHeader =
            mkEnableOption ''
              forwarding the client's Host header to the target instead of the
              target's own address.

              Off is netbird-proxy's default and it is the wrong one here. With
              it off the backend is dialled with `Host: <peer-ip>:<port>`, and
              anything that builds an absolute URL from the request builds it
              out of that — so an unauthenticated hit on radarr.lvdar.nl
              answers `Location: http://100.68.151.172:7878/login`, sending the
              browser off the public name and onto a mesh address that only
              resolves for someone already on the VPN. Cookie domains and
              absolute asset URLs go the same way.

              On by default because none of these targets does name-based
              virtual hosting — each is one application owning one port, which
              serves whatever Host it is given. A target that did would need
              this off, and its own hostname sent instead
            ''
            // {
              # There is no Host header in a raw connection, so this only means
              # anything at L7.
              default = config.mode == "http";
              defaultText = "mode == \"http\"";
            };

          targets = mkOption {type = listOf target;};
          crowdsec = mkOption {
            type = enum ["off" "observe" "enforce"];
            default = "enforce";
            description = ''
              Whether netbird-proxy checks each request's source against
              CrowdSec's local API before forwarding it. "observe" logs the
              verdict without acting on it, which is how to find out what a
              new scenario would have blocked.

              Only meaningful where services.crowdsec is on the same host; with
              no LAPI to ask, the proxy fails open.
            '';
          };

          bearerAuth = {
            enable =
              mkEnableOption "a NetBird identity check in front of this service"
              // {default = true;};
            groups = mkOption {
              type = listOf str;
              default = ["netbird-${name}"];
              defaultText = "[\"netbird-<name>\"]";
              description = ''
                NetBird group names allowed through. Resolved to ids at
                activation time, same as peers.

                One group per service by default, because these are the groups
                a *user* is in, and NetBird fills them from the `groups` claim
                in the IdP's token — so kanidm decides who reaches what, and
                granting somebody sonarr and nothing else takes one group
                membership there.

                Not "All": that group holds peers, not users, so gating on it
                let nobody in at all — every published service answered with a
                login that could never succeed.

                A name here must exist as a kanidm group whose claim map emits
                it (services/kanidm.nix), or the check can never pass.
              '';
            };
          };
        };
      });

      # Peer and group *names* here; the reconciler swaps them for ids.
      desiredFile = pkgs.writeText "netbird-services.json" (
        builtins.toJSON (
          lib.mapAttrsToList (name: s: {
            name = "${managedPrefix}${name}";
            inherit (s) domain mode enabled;
            listen_port = s.listenPort;
            pass_host_header = s.passHostHeader;
            targets = map (t:
              {
                inherit (t) peer port protocol;
                target_type = "peer";
                enabled = true;
              }
              // lib.optionalAttrs (t.path != null) {inherit (t) path;})
            s.targets;
            # Nested under `auth`, not alongside it. The API accepts an
            # unknown top-level `bearer_auth` without complaint and drops it, so
            # every service was published ungated while the reconciler reported
            # success — visible only as `"auth": {}` on a GET.
            access_restrictions.crowdsec_mode = s.crowdsec;
            auth.bearer_auth = {
              enabled = s.bearerAuth.enable;
              distribution_groups = s.bearerAuth.groups;
            };
          })
          cfg.services
        )
      );

      # netbird-proxy authenticates to the LAPI as a bouncer, and a bouncer key
      # is minted by cscli at runtime — there is no way to know it at build
      # time, and putting one in sops would mean a secret whose only consumer
      # is a service on the same host that could just as well generate it.
      crowdsecKeyFile = "/var/lib/netbird-proxy/crowdsec-bouncer.key";

      # Path component of the OIDC discovery URL, so the bootstrap cache below
      # can match the one request management makes before it will start. Null if
      # configEndpoint is not a URL this can parse, which simply leaves the
      # fallback out rather than generating a broken location.
      oidcPath = let
        m = builtins.match "https?://[^/]+(/.*)" cfg.oidc.configEndpoint;
      in
        if m == null
        then null
        else builtins.head m;

      reconcile = pkgs.writeShellApplication {
        name = "netbird-reconcile-services";
        runtimeInputs = with pkgs; [curl jq];
        text = ''
          # Straight to management's own listener. Going out via the public
          # name would need DNS that may not exist yet, TLS, and the transitional
          # port — three ways to fail for a request that never has to leave the
          # host. nginx only proxies /api here anyway.
          api="http://127.0.0.1:${toString mgmtPort}/api"
          token="$(cat "$CREDENTIALS_DIRECTORY/api-token")"

          req() {
            curl -sSf \
              -H "Authorization: Token $token" \
              -H "Content-Type: application/json" \
              "$@"
          }

          # Readiness gate. On a fresh control plane management is still coming
          # up and the API token is a placeholder, and while the mesh is being
          # built peers appear one at a time. None of that is an error, and
          # exiting non-zero for it makes switch-to-configuration fail, which
          # deploy-rs turns into a rollback — so this converges quietly and
          # leaves the rest for the next timer tick.
          if ! peers="$(req "$api/peers" 2>/dev/null)"; then
            echo "netbird: management not reachable or API token not accepted yet; nothing to do"
            exit 0
          fi

          # Group membership is only meaningful if NetBird is actually reading
          # the IdP's claim, and that is an account setting rather than
          # anything in management.json — off by default, with the claim name
          # empty. Left alone, every bearer check fails closed for everyone.
          #
          # Merged into the current settings rather than PUT wholesale: the
          # object carries the network ranges and expiry policy too, and a
          # partial replace would quietly reset them.
          account="$(req "$api/accounts" | jq -r '.[0]')"
          account_id="$(jq -r .id <<<"$account")"
          settings="$(jq '.settings
            | .jwt_groups_enabled = true
            | .jwt_groups_claim_name = "groups"' <<<"$account")"

          if [ "$(jq -r '.jwt_groups_enabled, .jwt_groups_claim_name' <<<"$settings" | tr '\n' ' ')" \
               != "$(jq -r '.settings.jwt_groups_enabled, .settings.jwt_groups_claim_name' <<<"$account" | tr '\n' ' ')" ]; then
            echo "netbird: enabling JWT group sync on the account"
            req -X PUT -d "$(jq -n --argjson s "$settings" '{settings: $s}')" \
              "$api/accounts/$account_id" >/dev/null \
              || echo "netbird: WARNING could not enable JWT group sync"
          fi

          # NetBird creates a group the first time a token carries its name, so
          # a freshly declared one does not exist until somebody happens to log
          # in — and until then every service gated on it is skipped. Create
          # them here instead, so the declared state converges on its own. JWT
          # sync then matches these by name rather than making duplicates.
          groups="$(req "$api/groups")"
          missing="$(jq -r --argjson have "$groups" '
            [.[] | select(.auth.bearer_auth.enabled) | .auth.bearer_auth.distribution_groups[]]
            | unique - [$have[].name] | .[]' ${desiredFile})"

          if [ -n "$missing" ]; then
            while read -r name; do
              echo "netbird: creating group $name"
              req -X POST -d "$(jq -n --arg n "$name" '{name: $n}')" \
                "$api/groups" >/dev/null || echo "netbird: WARNING group $name not created"
            done <<<"$missing"
            groups="$(req "$api/groups")"
          fi

          # NetBird's own SSH server, which is what `netbird ssh <peer>` talks
          # to — not the OpenSSH on the same port. Its client offers no SSH
          # auth method at all (it authenticates through the mesh), so against
          # OpenSSH it can only ever fail with "attempted methods [none]".
          #
          # `ssh_enabled` is management's half of the switch and defaults false,
          # so this stays off until asked for. The PUT carries the expiry and
          # approval fields as they are: the endpoint replaces the peer rather
          # than patching it, and omitting them resets them.
          for peer_name in ${lib.escapeShellArgs cfg.sshPeers}; do
            peer="$(jq -c --arg n "$peer_name" '.[] | select(.name == $n)' <<<"$peers")"

            if [ -z "$peer" ]; then
              echo "netbird: WARNING no peer named $peer_name to enable ssh on"
              continue
            fi

            [ "$(jq -r .ssh_enabled <<<"$peer")" = "true" ] && continue

            echo "netbird: enabling the ssh server on $peer_name"
            req -X PUT -d "$(jq -c '{
                name,
                ssh_enabled: true,
                login_expiration_enabled,
                inactivity_expiration_enabled,
                approval_required,
              }' <<<"$peer")" \
              "$api/peers/$(jq -r .id <<<"$peer")" >/dev/null \
              || echo "netbird: WARNING could not enable ssh on $peer_name"
          done

          # Point every peer at the fleet resolver. A "primary" nameserver
          # group in NetBird means "use this for all domains", which is why it
          # carries no domain list — the two are mutually exclusive in the API.
          #
          # The address is looked up rather than configured: NetBird assigns it
          # at enrollment, so a re-enrolled peer would otherwise leave the whole
          # mesh pointing at an address nothing answers on.
          ${lib.optionalString (cfg.dnsPeers != []) ''
            want=${lib.escapeShellArg (builtins.toJSON cfg.dnsPeers)}
            dns_ips="$(jq -c --argjson want "$want" \
              '[$want[] as $n | .[] | select(.name == $n) | .ip]' <<<"$peers")"
            all_group="$(jq -r '.[] | select(.name == "All") | .id' <<<"$groups" | head -n1)"

            if [ "$(jq length <<<"$dns_ips")" != "$(jq length <<<"$want")" ] || [ -z "$all_group" ]; then
              echo "netbird: waiting on peers/group All before setting DNS"
            else
              ns_name="${managedPrefix}resolver"
              desired_ns="$(jq -n \
                --arg name "$ns_name" \
                --argjson ips "$dns_ips" \
                --arg group "$all_group" \
                --arg peers "${lib.concatStringsSep ", " cfg.dnsPeers}" '{
                  name: $name,
                  description: ("unbound on " + $peers),
                  nameservers: [$ips[] | {ip: ., ns_type: "udp", port: 53}],
                  enabled: true,
                  groups: [$group],
                  primary: true,
                  domains: [],
                  search_domains_enabled: false,
                }')"

              existing_ns="$(req "$api/dns/nameservers")"
              ns_id="$(jq -r --arg n "$ns_name" \
                '.[] | select(.name == $n) | .id' <<<"$existing_ns" | head -n1)"

              if [ -n "$ns_id" ]; then
                # Only PUT on a real change: this runs every five minutes and
                # each write pushes a new network map to every peer.
                current="$(jq -c --arg n "$ns_name" \
                  '.[] | select(.name == $n)
                   | {name, description, nameservers, enabled, groups, primary,
                      domains, search_domains_enabled}' <<<"$existing_ns")"
                if [ "$(jq -cS . <<<"$current")" != "$(jq -cS . <<<"$desired_ns")" ]; then
                  echo "netbird: updating the fleet resolvers"
                  req -X PUT -d "$desired_ns" "$api/dns/nameservers/$ns_id" >/dev/null \
                    || echo "netbird: WARNING resolver not updated"
                fi
              else
                echo "netbird: pointing every peer at $(jq -r 'join(", ")' <<<"$dns_ips") for DNS"
                req -X POST -d "$desired_ns" "$api/dns/nameservers" >/dev/null \
                  || echo "netbird: WARNING resolver not created"
              fi
            fi
          ''}

          existing="$(req "$api/reverse-proxies/services")"

          # Resolve peer and group names to ids, marking anything that has not
          # appeared yet rather than failing the whole run.
          annotated="$(jq \
            --argjson peers "$peers" \
            --argjson groups "$groups" '
            def peer_id($n): ([$peers[] | select(.name == $n) | .id] | first);
            def group_id($n): ([$groups[] | select(.name == $n) | .id] | first);

            map(
              .targets |= map(.target_id = peer_id(.peer))
              | .auth.bearer_auth.distribution_groups |= map({name: ., id: group_id(.)})
            )' ${desiredFile})"

          # Anything still waiting on a peer or group is reported, not failed:
          # a name that never resolves shows up as a recurring warning here.
          jq -r '
            .[] | select(
              (any(.targets[]; .target_id == null))
              or (.auth.bearer_auth.enabled
                  and any(.auth.bearer_auth.distribution_groups[]; .id == null))
            )
            | "netbird: \(.name) waiting on " + (
                [(.targets[] | select(.target_id == null) | "peer " + .peer),
                 (.auth.bearer_auth.distribution_groups[] | select(.id == null) | "group " + .name)]
                | join(", ")
              )' <<<"$annotated"

          desired="$(jq '
            [.[] | select(
              (all(.targets[]; .target_id != null))
              and ((.auth.bearer_auth.enabled | not)
                   or all(.auth.bearer_auth.distribution_groups[]; .id != null))
            )]
            | map(
              .targets |= map(del(.peer))
              | .auth.bearer_auth.distribution_groups |= map(.id)
            )' <<<"$annotated")"

          echo "$desired" | jq -c '.[]' | while read -r svc; do
            name="$(jq -r .name <<<"$svc")"
            id="$(jq -r --arg n "$name" \
              '.[] | select(.name == $n) | .id' <<<"$existing" | head -n1)"

            # One service must not take the run down with it. A 409 means its
            # domain belongs to a service made outside nix — which the prefix
            # rule deliberately refuses to touch — and aborting there would
            # leave every service after it in the list unreconciled, silently.
            if [ -n "$id" ]; then
              # Only PUT on a real difference. Every PUT makes management
              # re-provision the service — reissuing its certificate and
              # re-reading the IdP's discovery document — so an unconditional
              # write here meant ~19 of those every five minutes, forever, for
              # a config that had not changed. It showed up as kanidm being
              # hammered on /.well-known/openid-configuration, which is a long
              # way from the thing that caused it.
              #
              # Both sides through the same normaliser. A projection of the
              # top-level keys alone is not enough: the API also decorates
              # each *target* with `host` and `options`, and reports an unset
              # listen_port as 0 rather than null — so a naive compare finds
              # drift in everything and writes every run anyway.
              norm='def n: {
                  name, domain, mode, enabled,
                  listen_port: (.listen_port // 0),
                  pass_host_header: (.pass_host_header // false),
                  crowdsec: (.access_restrictions.crowdsec_mode // "off"),
                  bearer_enabled: (.auth.bearer_auth.enabled // false),
                  # Only meaningful when the check is on. With bearer auth off
                  # the API stores [""] while we send the resolved id, so
                  # comparing them made every ungated service look changed
                  # forever — which was eleven of nineteen.
                  bearer_groups: (
                    if (.auth.bearer_auth.enabled // false)
                    then ((.auth.bearer_auth.distribution_groups // [])
                          | map(select(. != null and . != "")) | sort)
                    else [] end
                  ),
                  targets: ([.targets[] | {port, protocol, target_type, target_id}]
                            | sort_by(.target_id, .port))
                }; n'

              current="$(jq -cS --arg n "$name" "[.[] | select(.name == \$n)][0] | $norm" <<<"$existing")"
              wanted="$(jq -cS "$norm" <<<"$svc")"

              if [ "$current" = "$wanted" ]; then
                continue
              fi

              echo "netbird: updating $name"
              req -X PUT -d "$svc" "$api/reverse-proxies/services/$id" >/dev/null \
                || echo "netbird: WARNING $name not updated"
            else
              echo "netbird: creating $name"
              req -X POST -d "$svc" "$api/reverse-proxies/services" >/dev/null \
                || echo "netbird: WARNING $name not created — is its domain taken by a service not managed here?"
            fi
          done

          # Prune only what we own: anything carrying the managed prefix that is
          # no longer declared. Services made by hand are left alone — and so
          # are declared-but-not-yet-ready ones, hence $annotated rather than
          # $desired: pruning against the ready set would delete a service the
          # moment its peer went offline.
          jq -r --arg p '${managedPrefix}' --argjson d "$annotated" '
            [$d[].name] as $declared
            | .[]
            | select(.name | startswith($p))
            | select(.name | IN($declared[]) | not)
            | "\(.id) \(.name)"' <<<"$existing" |
          while read -r id name; do
            echo "netbird: removing $name"
            req -X DELETE "$api/reverse-proxies/services/$id" >/dev/null
          done
        '';
      };
    in {
      options.cosmos.services.netbird = {
        baseDomain = mkOption {
          type = str;
          default = "lvdar.nl";
          description = ''
            Cluster domain of the reverse proxy. Every published service is a
            subdomain of it, which works without registering custom domains
            because `*.lvdar.nl` already resolves to this host.
          '';
        };

        localTlsPort = mkOption {
          type = port;
          default = 4443;
          description = ''
            Loopback port the control-plane vhost listens on. Public :443 is
            owned by the SNI splitter, which forwards here by name.
          '';
        };

        proxyPort = mkOption {
          type = port;
          default = 9444;
          description = ''
            Loopback port netbird-proxy listens on, behind the SNI splitter.

            NOT 8443: that is gerbil's proxy listener. netbird-proxy binds its
            socket before it validates its token, so even while crash-looping it
            held the port, gerbil could not start, and traefik — which has
            Requires=gerbil — took every public domain down with it.

            Also avoid 8080 and 8444, netbird-proxy's own health and debug
            endpoints, and 9090, netbird management's metrics port.
          '';
        };

        oidc = {
          configEndpoint = mkOption {
            type = str;
            default = "https://auth.lvdar.nl/oauth2/openid/netbird/.well-known/openid-configuration";
          };
          authority = mkOption {
            type = str;
            default = "https://auth.lvdar.nl/oauth2/openid/netbird";
          };
          clientId = mkOption {
            type = str;
            default = "netbird";
          };

          # The IdP is the one thing that cannot be published through
          # netbird-proxy. Management fetches the discovery document at startup
          # and exits if it fails; the proxy cannot route anywhere until
          # management is up. Serving the IdP from the proxy therefore closes a
          # loop with no way in — which is exactly what retiring Pangolin did,
          # since Pangolin's traefik had been the independent path all along:
          # management crash-looped, the proxy answered 502 for every domain,
          # and no amount of retrying could break the tie.
          #
          # So gaia's own nginx publishes it instead, terminating with the same
          # wildcard certificate and forwarding straight over the mesh. Only the
          # SNI split and the mesh have to work, and neither needs management.
          idp = {
            domain = mkOption {
              type = nullOr str;
              default = null;
              example = "auth.lvdar.nl";
              description = ''
                Domain of the OIDC provider, served from this host's nginx
                rather than through netbird-proxy. Null leaves it to the proxy,
                which is only safe if the control plane's own IdP lives
                somewhere else entirely.
              '';
            };
            upstream = mkOption {
              type = nullOr str;
              default = null;
              example = "https://100.68.151.172:8443";
              description = ''
                Where that domain is proxied to — the IdP peer's mesh address.
                An address, not a name: nginx resolves a literal `proxy_pass`
                host once at startup, so a name would make nginx's boot depend
                on NetBird's resolver being up first.
              '';
            };
          };
        };

        services = mkOption {
          type = attrsOf service;
          default = {};
          description = ''
            Reverse-proxy services, reconciled against the management API on
            activation. Peers and groups are given by name, not id.
          '';
        };

        dnsPeers = mkOption {
          type = listOf str;
          default = [];
          example = ["endeavour" "gaia"];
          description = ''
            Peers whose resolvers every other peer should use, in order.

            More than one is worth having: a single entry makes DNS for the
            whole mesh depend on one host. Clients fall through to the next on
            failure, so order by preference — and every entry should carry the
            *same* blocklist, since a fallback that answers but stops blocking
            ads is a confusing failure mode when you cannot tell which one
            served you.

            NetBird pushes this to peers as a primary nameserver group, so it
            answers for *all* domains — which is the point: that peer already
            runs unbound with the oisd blocklist, so making it the fleet
            resolver gives every device ad-blocking DNS wherever it roams,
            rather than only at home.

            The peer's mesh address is resolved from the API at reconcile time
            rather than written here, so it survives a re-enrollment that
            changes the address. That peer must be able to answer on the mesh:
            see cosmos.services.unbound.mesh, which opens access-control to the
            CGNAT range and forwards the mesh domain back to the local agent.

            Every peer listed must be able to answer on the mesh: see
            cosmos.services.unbound.mesh.
          '';
        };

        sshPeers = mkOption {
          type = listOf str;
          default = [];
          example = ["endeavour" "gaia" "pioneer"];
          description = ''
            Peers to turn NetBird's own SSH server on for, by name, so that
            `netbird ssh <peer>` works against them.

            Two switches have to agree and only one of them lives on the peer.
            `ServerSSHAllowed` in the client's config.json is the peer saying it
            is willing (services/netbird.nix sets it, and current NetBird
            defaults it on anyway); `ssh_enabled` on the peer object is
            management saying so, defaults false, and is settable only through
            the API — hence here. A peer with the first and not the second
            reports "SSH Server: Disabled" while its config plainly says
            otherwise, which is a confusing place to end up.

            This is a shell on the peer, reachable from the mesh, authorised by
            the IdP token rather than by anything in _ssh-keys — access is a
            group membership to grant or revoke rather than a key to
            distribute. OpenSSH keeps running alongside it; the two answer on
            the same port on different addresses.

            Note that NetBird 0.74's API exposes only `ssh_enabled`. The
            further per-peer flags the agent understands — root login, SFTP,
            port forwarding — exist on the management-to-peer protobuf but
            have no REST or environment surface, so they cannot be set from
            here and stay at whatever management defaults them to.
          '';
        };
      };

      config = {
        sops.secrets = {
          # coturn's preStart substitutes this into turnserver.cfg, and that
          # runs as the service user — not root — so a root-only secret gives
          # it EACCES and the unit never starts.
          "keys/netbird/coturn-password".owner = "turnserver";
          "keys/netbird/turn-secret" = {};
          "keys/netbird/datastore-encryption-key" = {};
          "keys/netbird/proxy-token" = {};
          "keys/netbird/api-token" = {};
        };

        cosmos.system.impermanence.persist.directories =
          [
            {
              directory = "/var/lib/netbird-mgmt";
              user = "root";
              group = "root";
              mode = "0750";
            }
            {
              directory = "/var/lib/netbird-proxy";
              user = "root";
              group = "root";
              mode = "0750";
            }
          ]
          # The bootstrap cache has to survive the root-subvolume wipe, or
          # impermanence would discard it on exactly the boots that need it.
          ++ lib.optional (cfg.oidc.idp.domain != null && oidcPath != null) {
            directory = "/var/cache/nginx";
            user = "nginx";
            group = "nginx";
            mode = "0700";
          };

        # netbird-mgmt fetches the OIDC discovery document at startup and exits
        # if it cannot. kanidm is published through the very reverse proxy this
        # host runs, so any blip there crash-loops management, systemd's default
        # rate limiter parks it in `failed`, switch-to-configuration exits
        # non-zero and deploy-rs rolls the whole deploy back — leaving the proxy
        # still broken. Disabling the limiter keeps `Restart=always` retrying
        # forever instead, so the host stays deployable and management recovers
        # on its own once the IdP answers.
        systemd.services.netbird-management.unitConfig.StartLimitIntervalSec = 0;
        systemd.services.netbird-proxy.unitConfig.StartLimitIntervalSec = 0;

        services.netbird.server = {
          enable = true;
          enableNginx = true;
          inherit (cfg) domain;

          coturn = {
            enable = true;
            passwordFile = config.sops.secrets."keys/netbird/coturn-password".path;
          };

          management = {
            inherit (cfg) dnsDomain;
            oidcConfigEndpoint = cfg.oidc.configEndpoint;
            singleAccountModeDomain = cfg.dnsDomain;

            settings = {
              DataStoreEncryptionKey._secret =
                config.sops.secrets."keys/netbird/datastore-encryption-key".path;

              # Signs time-based TURN credentials. The module's default is a
              # literal placeholder, which lands world-readable in the store and
              # (rightly) warns — and this flake builds with abort-on-warn.
              TURNConfig.Secret._secret =
                config.sops.secrets."keys/netbird/turn-secret".path;

              # Both the SNI splitter and the proxy sit in front, and both speak
              # PROXY protocol, so the only trustworthy hop is loopback.
              ReverseProxy = {
                TrustedHTTPProxies = ["127.0.0.1/32"];
                TrustedHTTPProxiesCount = 1;
              };

              # The dashboard is a browser app: PKCE, no client secret. The
              # authorization and token endpoints are deliberately left unset —
              # management fills them from the OIDC discovery document, and
              # hardcoding kanidm's would just be a second place to get wrong.
              PKCEAuthorizationFlow.ProviderConfig = {
                Audience = cfg.oidc.clientId;
                ClientID = cfg.oidc.clientId;

                # Loopback only. This flow belongs to the CLI, which completes
                # it on a listener it opens itself — the dashboard has its own
                # OIDC config and never reads this. The dashboard's callback
                # was listed here first, and NewPKCEAuthorizationFlow takes the
                # first URL whose port it cannot already connect to: with no
                # port to parse it dialled "netbird.lvdar.nl:", failed, called
                # that free, and sent the browser to the dashboard carrying a
                # code meant for the CLI. kanidm allowed the redirect and the
                # dashboard then answered "there was an error logging you in".
                #
                # Two ports so a busy 53000 is not the end of it; both are in
                # the client's originUrl in services/kanidm.nix.
                RedirectURLs = [
                  "http://localhost:53000"
                  "http://localhost:54000"
                ];
              };

              # The module hardcodes :443 here; peers dial whatever the splitter
              # actually listens on.
              Signal.URI = "${cfg.domain}:${toString cfg.publicPort}";

              # Without these the dashboard authenticates but every API call is
              # rejected, so it sits on a loading spinner forever.
              #
              # ApplyOIDCConfig fills AuthIssuer and AuthKeysLocation from the
              # discovery document, but the audience cannot be derived and
              # netbird only sets it on the EmbeddedIdP path, which is not in
              # use here. Left empty, GetAuthAudiences returns [""], and
              # jwt.WithAudience("") demands an `aud` containing the empty
              # string — so validation can never succeed.
              HttpConfig = {
                AuthAudience = cfg.oidc.clientId;
                # Used for the reverse proxy's browser-auth flow.
                AuthClientID = cfg.oidc.clientId;
                # kanidm puts the user id in `sub`. netbird only defaults this
                # alongside its embedded IdP, so it too has to be explicit.
                AuthUserIDClaim = "sub";

                # Where the IdP sends the browser back after a bearer-auth
                # login. Management serves this itself, on its own API and
                # exempt from its own auth middleware, and the service the user
                # was heading for rides along in the signed `state` — so it is
                # one URL for every published domain, not one per domain.
                #
                # Left unset, the authorization request goes out with no
                # `redirect_uri` at all and the IdP rejects it before the login
                # form. netbird only fills this in alongside its embedded IdP,
                # which is not in use here — the same gap as the two settings
                # above. types.ProxyCallbackEndpointFull fixes the path.
                AuthCallbackURL = "${authority}/api/reverse-proxy/callback";
              };
            };
          };

          dashboard = {
            # server.nix hardcodes "https://${domain}" at normal priority, which
            # is only right when the splitter is on 443.
            managementServer = lib.mkForce authority;
            settings = {
              AUTH_AUTHORITY = cfg.oidc.authority;
              AUTH_CLIENT_ID = cfg.oidc.clientId;
              AUTH_AUDIENCE = cfg.oidc.clientId;

              # Move the OIDC callbacks off hash routes. Left unset, the
              # dashboard redirects to `/#callback` and `/#silent-callback`,
              # which kanidm can never match: it strips the fragment from
              # configured origins (RFC 6749 §3.1.2) while the incoming
              # redirect_uri keeps it, so strict matching always fails — see
              # kanidm#3217. NetBird's own setup.env.example exposes these two
              # overrides for exactly this, and fixing it here rather than
              # disabling kanidm's strict validation keeps the check on.
              #
              # These must be paths the dashboard has no page at. Its OIDC
              # router matches on path alone — `eo(location.href) === eo(
              # redirect_uri)` — with no test for a `code` parameter, so
              # whatever path is named here stops being a page and becomes the
              # callback handler forever. Pointing it at `/peers` (NetBird's
              # own docs suggest that pair) therefore replaced the dashboard's
              # landing page with a callback that had no code to redeem: login
              # at kanidm succeeded, the real callback was consumed, and the
              # app then navigated to a `/peers` that could only ever render
              # the "authenticating" spinner.
              #
              # Nothing is exported at these two paths, so nginx serves the
              # SPA shell for them below; the client-side router takes it from
              # there.
              #
              # Must stay in step with the netbird originUrl list in
              # services/kanidm.nix.
              AUTH_REDIRECT_URI = "/callback";
              AUTH_SILENT_REDIRECT_URI = "/silent-callback";
            };
          };
        };

        # The netbird modules contribute locations to this vhost but no listener
        # and no TLS, which is left to us. It is deliberately loopback-only: the
        # SNI splitter below owns the public socket.
        services.nginx.virtualHosts =
          {
            # Everything the splitter sends here shares one wildcard
            # certificate, and that is all HTTP/2 connection coalescing needs: a
            # browser holding a connection to netbird.lvdar.nl or auth.lvdar.nl
            # will reuse it for *any* other *.lvdar.nl name rather than open a
            # second one — same address, and the certificate already covers the
            # name. Those requests arrive with a Host no server here matches,
            # fall through to the default server, and every published domain
            # quietly becomes whichever vhost sorted first. Which is how
            # jellyfin.lvdar.nl and friends started answering with kanidm's
            # login page, while curl — one connection per host, correct SNI
            # every time — saw nothing wrong.
            #
            # 421 is the defined answer: the client drops the coalesced
            # connection and retries on a new one, whose SNI routes it to
            # netbird-proxy as intended. Saying it still requires a certificate.
            "_" = {
              default = true;
              onlySSL = true;
              useACMEHost = "lvdar.nl";
              listen = [
                {
                  addr = "127.0.0.1";
                  port = cfg.localTlsPort;
                  ssl = true;
                  proxyProtocol = true;
                }
              ];
              extraConfig = "return 421;";
            };

            ${cfg.domain} = {
              onlySSL = true;
              useACMEHost = "lvdar.nl";
              listen = [
                {
                  addr = "127.0.0.1";
                  port = cfg.localTlsPort;
                  ssl = true;
                  proxyProtocol = true;
                }
              ];
              # The OIDC callback paths are not exported routes, so the
              # dashboard's `try_files` would 404 them. The static export's 404
              # page carries the same root layout — and so the same OidcProvider —
              # as every other page, which is all the callback needs; this only
              # serves it as a 200 rather than relying on the vhost's error_page.
              locations = lib.genAttrs ["= /callback" "= /silent-callback"] (_: {
                extraConfig = "try_files /404.html =404;";
              });

              extraConfig = ''
                set_real_ip_from 127.0.0.1;
                real_ip_header proxy_protocol;
              '';
            };
          }
          # The IdP, published here rather than through the proxy that depends on
          # it. `proxy_ssl_verify` stays off because the peer answers with the
          # wildcard certificate for its public name, which cannot match the mesh
          # address dialled to reach it; the hop is inside WireGuard either way.
          // lib.optionalAttrs (cfg.oidc.idp.domain != null) {
            ${cfg.oidc.idp.domain} = {
              onlySSL = true;
              useACMEHost = "lvdar.nl";
              listen = [
                {
                  addr = "127.0.0.1";
                  port = cfg.localTlsPort;
                  ssl = true;
                  proxyProtocol = true;
                }
              ];
              locations =
                {"/".proxyPass = cfg.oidc.idp.upstream;}
                // lib.optionalAttrs (oidcPath != null) {
                  # Breaks a hard bootstrap deadlock that takes the whole ingress
                  # down on every cold boot:
                  #
                  #   netbird-management exits unless it can fetch this document
                  #     -> the document is served here, proxied to the IdP peer
                  #       -> that peer is only reachable over the mesh
                  #         -> the mesh is brought up by netbird-management
                  #
                  # Nothing in that loop retries its way out — management hard-
                  # exits, and `StartLimitIntervalSec = 0` only means it retries
                  # forever against a dependency that can never appear. On
                  # 2026-08-12 recovering from it needed a reverse SSH tunnel and
                  # a hand-written DNAT rule.
                  #
                  # `proxy_cache_use_stale` answers from the last successful
                  # fetch while the peer is unreachable, which is exactly long
                  # enough for management to start and bring the mesh up; the
                  # entry then refreshes from the live document. A cached copy
                  # rather than a checked-in one on purpose — a static file would
                  # silently drift from whatever kanidm actually serves, and this
                  # cannot, because it *is* what kanidm last served.
                  "= ${oidcPath}" = {
                    proxyPass = "${cfg.oidc.idp.upstream}${oidcPath}";
                    extraConfig = ''
                      proxy_ssl_verify off;
                      proxy_cache oidc_bootstrap;
                      # kanidm answers this with
                      #   cache-control: no-store, no-cache, max-age=0
                      #   pragma: no-cache
                      # which nginx honours by storing nothing — so without
                      # this the cache is empty at exactly the moment the
                      # fallback is needed, and the deadlock is untouched. That
                      # is not hypothetical: the first version of this fix was
                      # deployed, looked correct, and cached nothing.
                      #
                      # Overriding it is safe *here* and only here: the location
                      # is an exact match on the discovery document, which is
                      # public, non-personalised metadata carrying no session or
                      # token material. The directive does not apply to the rest
                      # of the IdP, which keeps its no-store semantics.
                      proxy_ignore_headers Cache-Control Expires Set-Cookie;
                      proxy_cache_valid 200 10m;
                      proxy_cache_use_stale error timeout
                        http_500 http_502 http_503 http_504;
                      proxy_cache_background_update on;
                      proxy_cache_lock on;
                      # Bounded so a dead peer fails over to the cache quickly
                      # instead of sitting in management's startup timeout.
                      proxy_connect_timeout 3s;
                      proxy_read_timeout 5s;
                    '';
                  };
                };
              extraConfig = ''
                set_real_ip_from 127.0.0.1;
                real_ip_header proxy_protocol;
                proxy_ssl_verify off;
              '';
            };
          };

        # Backing store for the bootstrap cache above. inactive is a year
        # because the entry has to still be there after an outage of arbitrary
        # length — the one moment it is needed is a cold boot with the IdP
        # unreachable, and an entry expired for inactivity would put the deadlock
        # right back. It holds a single small JSON document.
        services.nginx.appendHttpConfig = lib.mkIf (cfg.oidc.idp.domain != null && oidcPath != null) ''
          proxy_cache_path /var/cache/nginx/oidc-bootstrap
            levels=1:2 keys_zone=oidc_bootstrap:1m max_size=1m
            inactive=365d use_temp_path=off;
        '';

        # Split the public port by SNI without terminating. netbird-proxy
        # answers ACME tls-alpn-01 challenges on this socket, so decrypting
        # here would break its certificate renewal.
        services.nginx.streamConfig = ''
          map $ssl_preread_server_name $netbird_upstream {
            ${cfg.domain}  127.0.0.1:${toString cfg.localTlsPort};
            ${lib.optionalString (cfg.oidc.idp.domain != null)
            "${cfg.oidc.idp.domain}  127.0.0.1:${toString cfg.localTlsPort};"}
            default        127.0.0.1:${toString cfg.proxyPort};
          }

          server {
            listen ${toString cfg.publicPort};
            listen [::]:${toString cfg.publicPort};
            ssl_preread on;
            proxy_protocol on;
            proxy_pass $netbird_upstream;
          }
        '';

        # The public port, plus a port for each L4 service — those bypass the
        # SNI split entirely and are accepted by netbird-proxy directly.
        networking.firewall = let
          l4 = lib.filter (p: p != null) (lib.mapAttrsToList (_: s: s.listenPort) cfg.services);
        in {
          allowedTCPPorts = [cfg.publicPort] ++ l4;
          allowedUDPPorts =
            lib.mapAttrsToList (_: s: s.listenPort)
            (lib.filterAttrs (_: s: s.mode == "udp" && s.listenPort != null) cfg.services);
        };

        # Mints the proxy's bouncer key on first start and registers it. Both
        # halves are idempotent: the key is generated only when the file is
        # missing, and a re-register of the same name is tolerated so a
        # crowdsec database that has been wiped can be re-populated without
        # invalidating the key the proxy already holds.
        systemd.services.netbird-proxy-crowdsec = lib.mkIf config.services.crowdsec.enable {
          description = "Register netbird-proxy as a CrowdSec bouncer";
          after = ["crowdsec.service"];
          requires = ["crowdsec.service"];
          before = ["netbird-proxy.service"];
          wantedBy = ["netbird-proxy.service"];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StateDirectory = "netbird-proxy";
            StateDirectoryMode = "0750";
          };

          path = [config.services.crowdsec.package pkgs.openssl];

          script = ''
            key_file=${lib.escapeShellArg crowdsecKeyFile}

            if [ ! -s "$key_file" ]; then
              umask 077
              openssl rand -base64 32 | tr -d '\n' > "$key_file"
            fi

            cscli bouncers add netbird-proxy --key "$(cat "$key_file")" 2>/dev/null \
              || echo "netbird-proxy: bouncer already registered"
          '';
        };

        # nixpkgs packages netbird-proxy but ships no module for it, so this is
        # ours. It brings up its own WireGuard tunnel to the peers it forwards
        # to (hence NET_ADMIN), and reaches management over loopback so gRPC
        # never round-trips through the reverse proxy.
        systemd.services.netbird-proxy = {
          description = "NetBird reverse proxy";
          documentation = ["https://docs.netbird.io/manage/reverse-proxy"];

          after = ["network.target" "netbird-management.service"];
          wants = ["netbird-management.service"];
          wantedBy = ["multi-user.target"];

          environment =
            {
              NB_PROXY_DOMAIN = cfg.baseDomain;
              NB_PROXY_ADDRESS = ":${toString cfg.proxyPort}";
              NB_PROXY_MANAGEMENT_ADDRESS = "http://127.0.0.1:${toString mgmtPort}";
              NB_PROXY_ALLOW_INSECURE = "true";
              NB_PROXY_ACME_CERTIFICATES = "true";
              NB_PROXY_ACME_CHALLENGE_TYPE = "tls-alpn-01";
              NB_PROXY_CERTIFICATE_DIRECTORY = "/var/lib/netbird-proxy/certs";
              NB_PROXY_GEO_DATA_DIR = "/var/lib/netbird-proxy/geolocation";
              # The embedded NetBird client writes its firewall and DNS state
              # here. It defaults to /var/lib/netbird, which this service cannot
              # write to — ProtectSystem=strict makes everything outside its own
              # StateDirectory read-only — so it logged a failure every ten
              # seconds (109k of them since 30 July) and re-derived that state on
              # every restart instead of resuming it.
              #
              # Its own StateDirectory rather than granting write access to
              # /var/lib/netbird: that one belongs to the netbird agent running
              # alongside this, and pointing two daemons at one state.json would
              # trade a loud failure for a quiet one.
              NB_STATE_DIR = "/var/lib/netbird-proxy";
              # Client IPs would otherwise all read as 127.0.0.1, which would make
              # any CIDR or country restriction meaningless.
              NB_PROXY_PROXY_PROTOCOL = "true";
              NB_PROXY_TRUSTED_PROXIES = "127.0.0.1/32,::1/128";
              # Services live at <name>.lvdar.nl, never at the bare domain.
              NB_PROXY_REQUIRE_SUBDOMAIN = "true";
            }
            // lib.optionalAttrs config.services.crowdsec.enable {
              NB_PROXY_CROWDSEC_API_URL = "http://127.0.0.1:${toString config.cosmos.services.crowdsec.lapiPort}";
            };

          serviceConfig = {
            LoadCredential =
              [
                "token:${config.sops.secrets."keys/netbird/proxy-token".path}"
              ]
              ++ lib.optional config.services.crowdsec.enable
              "crowdsec-key:${crowdsecKeyFile}";
            Restart = "always";
            RestartSec = "5s";
            StateDirectory = "netbird-proxy";
            StateDirectoryMode = "0750";
            WorkingDirectory = "/var/lib/netbird-proxy";
            # NET_ADMIN for the WireGuard tunnel it brings up; NET_BIND_SERVICE
            # so an L4 service can publish a port below 1024.
            #
            # The second one is not hypothetical tidiness. Publishing the
            # tangled knot's git-over-SSH on :22 failed with
            #
            #   router for TCP port 22: listen tcp :22: bind: permission denied
            #
            # and the proxy logs it, ignores that one mapping and carries on —
            # so the service looks created, every other mapping keeps working,
            # and the port is simply never bound. Nothing needed this before
            # because the only other L4 publish is traccar-osmand on 5055.
            AmbientCapabilities = ["CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE"];
            CapabilityBoundingSet = ["CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE"];

            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            RestrictSUIDSGID = true;
          };

          # The token is credential-only, so it never reaches the unit file or
          # the store; export it just for the exec.
          script = ''
            export NB_PROXY_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/token")"
            ${lib.optionalString config.services.crowdsec.enable ''
              export NB_PROXY_CROWDSEC_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/crowdsec-key")"
            ''}
            exec ${lib.getExe pkgs.netbird-proxy}
          '';
        };

        # Driven by the timer below, deliberately NOT by multi-user.target.
        #
        # This cannot succeed until peers have enrolled and a real API token
        # exists, and both of those come *after* the control plane is first
        # deployed. A unit that fails during activation makes
        # switch-to-configuration exit non-zero, which deploy-rs reads as a
        # failed deploy and auto-rolls-back — so wiring it into the boot
        # target would make the control plane impossible to deploy at all.
        #
        # The timer retries until the world is ready; `systemctl start
        # netbird-services` forces it once the credentials are in place.
        systemd.services.netbird-services = {
          description = "Reconcile declared NetBird reverse-proxy services";
          after = ["netbird-management.service"];
          wants = ["netbird-management.service"];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe reconcile;
            LoadCredential = [
              "api-token:${config.sops.secrets."keys/netbird/api-token".path}"
            ];
          };
        };

        systemd.timers.netbird-services = {
          description = "Periodically reconcile NetBird reverse-proxy services";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "2min";
            OnUnitActiveSec = "5min";
            Unit = "netbird-services.service";
          };
        };
      };
    };
  };
}
