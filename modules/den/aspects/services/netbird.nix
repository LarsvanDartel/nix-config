# services.netbird — self-hosted NetBird mesh: agent, control plane and reverse proxy on gaia.
{
  den,
  lib,
  ...
}: let
  inherit (den.lib.policy) pipe;
in {
  den.quirks.netbird-service.description = "Public reverse-proxy services (cosmos.services.netbird.services entries), published by the NetBird server";

  # Payloads are `{host, ...}:`, never `{config, ...}:`; see docs/src/architecture.md#cross-host-data.
  # collect, not collectAll: every published app is x86_64. den reads these argument names; keep them.
  # deadnix: skip
  den.policies.netbird-service = {host, ...}: [
    (pipe.from "netbird-service" [
      (pipe.collect (
        # deadnix: skip
        {host, ...}: true
      ))
    ])
  ];

  den.quirks.netbird-proxy-reporter.description = "Mesh address of the host whose node-exporter reports netbird-proxy's mesh address, collected by services.netbird.proxy-target";

  # deadnix: skip
  den.policies.netbird-proxy-reporter = {host, ...}: [
    (pipe.from "netbird-proxy-reporter" [
      (pipe.collect (
        # deadnix: skip
        {host, ...}: true
      ))
    ])
  ];

  den.aspects.services.netbird.client.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) enum ints lines listOf nullOr port str;

    cfg = config.cosmos.services.netbird;

    aclWatchdog = pkgs.writeShellApplication {
      name = "netbird-acl-watchdog";
      runtimeInputs = with pkgs; [nftables systemd gnugrep];
      text = ''
        chain="netbird-acl-input-rules"

        if ! rules="$(nft list chain ip netbird "$chain" 2>/dev/null)"; then
          echo "netbird-acl-watchdog: no $chain yet, nothing to judge"
          exit 0
        fi

        # The chain is incomplete while the agent re-syncs at startup; restarting then could loop.
        active_us="$(systemctl show ${config.services.netbird.clients.default.suffixedName}.service \
          -p ActiveEnterTimestampMonotonic --value)"
        if [[ -n "$active_us" && "$active_us" != "0" ]]; then
          now_us="$(( $(cut -d' ' -f1 /proc/uptime | tr -d '.') * 10000 ))"
          if (( now_us - active_us < ${toString cfg.client.aclWatchdogGrace} * 1000000 )); then
            echo "netbird-acl-watchdog: agent started under ${toString cfg.client.aclWatchdogGrace}s ago, still converging"
            exit 0
          fi
        fi

        # Healthy = established accept plus a dport-less `@nb…` saddr accept (per-service rules carry a dport).
        # The set name is spelled @nb<digits> or @nb-<hex> by agent version; a narrower match restart-loops the agent.
        if grep -q 'ct state established,related.*accept' <<<"$rules" \
          && grep -qE 'ip saddr @nb[0-9a-f-]+ accept$' <<<"$rules"; then
          exit 0
        fi

        echo "netbird-acl-watchdog: mesh ACLs have decayed to per-service rules only; restarting the agent"
        echo "--- ruleset before restart ---"
        echo "$rules"
        systemctl restart ${config.services.netbird.clients.default.suffixedName}.service
      '';
    };

    # url.URL has no JSON marshalling, so config.json stores the expanded Go
    # struct; absent fields unmarshal to zero values.
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
        # Every host must agree; den gives an aspect no way to read another host's config.
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

        proxy = {
          reporter = mkOption {
            type = nullOr str;
            default = null;
            description = ''
              Mesh address of the host whose node-exporter reports netbird-proxy's
              current mesh address. Set by services.netbird.proxy-target from the
              `netbird-proxy-reporter` quirk; null on hosts netbird-proxy does not
              target. See docs/src/notes/services-netbird.md#proxy-address.
            '';
          };

          stateDir = mkOption {
            type = str;
            default = "/var/lib/netbird-proxy-trust";
            readOnly = true;
            description = "Where the followed address and the files rendered from it live.";
          };

          addressFile = mkOption {
            type = str;
            default = "${cfg.client.proxy.stateDir}/address";
            readOnly = true;
            description = ''
              netbird-proxy's mesh address, the source of every request it
              forwards here. Empty until first learned, never cleared after.
            '';
          };

          restartUnits = mkOption {
            type = listOf str;
            default = [];
            description = "Units that read the address only at start, restarted when it changes.";
          };
        };

        proxyRealIp = mkOption {
          type = lines;
          readOnly = true;
          # Glob: a missing file matches nothing instead of failing nginx, which then trusts nobody.
          default = lib.optionalString (cfg.client.proxy.reporter != null) ''
            include ${cfg.client.proxy.stateDir}/nginx-realip.conf*;
          '';
          description = ''
            nginx server-block directives restoring the visitor's address on
            a vhost netbird-proxy targets, so logs (and crowdsec) see the
            visitor rather than the proxy. X-Forwarded-For, not X-Real-IP:
            the proxy passes a client-sent X-Real-IP through untouched but
            appends to X-Forwarded-For, and recursion from the right with only
            the proxy trusted lands on the address it actually saw.

            Not for a vhost gated on proxyAllow: access rules would then
            see the visitor and refuse everyone.
          '';
        };

        proxyAllow = mkOption {
          type = lines;
          readOnly = true;
          default = lib.optionalString (cfg.client.proxy.reporter != null) ''
            include ${cfg.client.proxy.stateDir}/nginx-allow.conf*;
          '';
          description = ''
            nginx `allow` for netbird-proxy alone. Follow it with `deny all;`:
            the include matches nothing until the address is first learned.
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

      # XDG_CURRENT_DESKTOP makes `netbird ssh` use PKCE; its device flow fails with NotFound.
      # One block: a dynamic attribute path cannot be split across definitions.
      systemd.services.${config.services.netbird.clients.default.suffixedName} = {
        # The resolver address lives in config.json, not the unit; without this
        # the old agent keeps holding :53, which unbound wants.
        restartTriggers = [cfg.client.dnsResolverAddress];

        environment =
          lib.mkIf config.services.displayManager.enable
          {XDG_CURRENT_DESKTOP = "netbird-has-a-browser";};
      };

      # The agent can silently drop the policy rules from netbird-acl-input-rules, leaving only
      # per-service rules; a restart reinstates them. Restarts only on detected decay.
      systemd.services.netbird-acl-watchdog = lib.mkIf cfg.client.aclWatchdog {
        description = "Restart the NetBird agent if its mesh ACLs have decayed";
        # No wantedBy: a oneshot failing during activation makes deploy-rs roll back.
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe aclWatchdog;
        };
      };

      systemd.timers.netbird-acl-watchdog = lib.mkIf cfg.client.aclWatchdog {
        description = "Periodic NetBird mesh ACL check";
        wantedBy = ["timers.target"];
        timerConfig = {
          # Bounds mesh downtime after a decay; jitter would only widen it.
          OnBootSec = "90s";
          OnUnitActiveSec = cfg.client.aclWatchdogInterval;
          Unit = "netbird-acl-watchdog.service";
        };
      };

      cosmos.system.impermanence.persist.directories = [
        {
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

          # The agent rewrites config.json; stated so it is kept.
          config.ServerSSHAllowed = true;

          # Setup key: OIDC needs kanidm, which is published through the mesh. No systemdDependencies on
          # sops-install-secrets.service: that unit does not exist here and the agent stalls at NeedsLogin.
          login = {
            enable = true;
            setupKeyFile = config.sops.secrets."keys/netbird/setup-key".path;
          };

          # Keep a literal attrset: it merges with ServerSSHAllowed above only
          # while both are literals; `//` would collide.
          config = {
            ManagementURL = urlValue cfg.domain;
            AdminURL = urlValue cfg.domain;
            CustomDNSAddress = cfg.client.dnsResolverAddress;
          };
        };
      };
    };
  };

  den.aspects.services.netbird.proxy-target = {
    includes = with den.aspects.services; [netbird.client node-exporter den.policies.netbird-proxy-reporter];

    nixos = {
      config,
      lib,
      pkgs,
      netbird-proxy-reporter,
      ...
    }: let
      cfg = config.cosmos.services.netbird.client.proxy;
      dir = cfg.stateDir;

      # Uniform across the fleet (services/node-exporter.nix), so this host's port is the reporter's.
      metricsUrl = "http://${cfg.reporter}:${toString config.cosmos.services.node-exporter.port}/metrics?collect[]=textfile";

      follow = pkgs.writeShellApplication {
        name = "netbird-proxy-trust";
        runtimeInputs = with pkgs; [curl gnused coreutils systemd];
        text = ''
          cd ${dir}
          current="$(cat address 2>/dev/null || true)"

          # Any doubt keeps the current address: a reporter outage must not cut off a proxy that still works.
          if ! metrics="$(curl -fsSg --max-time 10 '${metricsUrl}')"; then
            echo "reporter unreachable; keeping ''${current:-nothing}"
            exit 0
          fi
          addr="$(sed -nE 's/^netbird_proxy_peer_info\{address="([0-9.]+)"\} 1$/\1/p' <<<"$metrics")"
          if [[ ! $addr =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
            echo "reporter names no single proxy peer; keeping ''${current:-nothing}"
            exit 0
          fi

          if [[ $addr != "$current" ]]; then
            printf 'set_real_ip_from %s;\nreal_ip_header X-Forwarded-For;\nreal_ip_recursive on;\n' "$addr" >nginx-realip.conf.tmp
            printf 'allow %s;\n' "$addr" >nginx-allow.conf.tmp
            printf '%s\n' "$addr" >address.tmp
            mv nginx-realip.conf.tmp nginx-realip.conf
            mv nginx-allow.conf.tmp nginx-allow.conf
            mv address.tmp address
            echo "netbird-proxy moved from ''${current:-nothing} to $addr"
            ${lib.optionalString config.services.nginx.enable "systemctl try-reload-or-restart nginx.service"}
            ${lib.optionalString (cfg.restartUnits != []) "systemctl try-restart ${lib.escapeShellArgs cfg.restartUnits}"}
          fi

          printf '# HELP netbird_proxy_trusted_info The netbird-proxy address this host trusts.\n# TYPE netbird_proxy_trusted_info gauge\nnetbird_proxy_trusted_info{address="%s"} 1\n' "$addr" >trusted.prom.tmp
          mv trusted.prom.tmp trusted.prom
        '';
      };
    in {
      assertions = [
        {
          assertion = lib.length netbird-proxy-reporter == 1;
          message = "services.netbird.proxy-target needs exactly one host with services.netbird; found ${toString (lib.length netbird-proxy-reporter)}.";
        }
      ];

      cosmos.services.netbird.client.proxy.reporter = lib.head (netbird-proxy-reporter ++ [null]);

      cosmos.system.impermanence.persist.directories = [
        {
          directory = dir;
          user = "root";
          group = "root";
          mode = "0755";
        }
      ];

      services.prometheus.exporters.node.extraFlags = ["--collector.textfile.directory=${dir}"];

      systemd.services.netbird-proxy-trust = {
        description = "Follow netbird-proxy's mesh address";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "netbird-proxy-trust";
          StateDirectoryMode = "0755";
          ExecStart = lib.getExe follow;
        };
      };

      systemd.timers.netbird-proxy-trust = {
        description = "Periodic netbird-proxy address check";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "1min";
          Unit = "netbird-proxy-trust.service";
        };
      };
    };
  };

  den.aspects.services.netbird = {
    # Only the server collects: a fleet-wide collect would make each host's
    # evaluation pull in every other host's config.
    includes = with den.aspects.services; [nginx netbird.client den.policies.netbird-service];

    scrape-target = {host, ...}: {
      job = "netbird";
      instance = host.name;
      port = 9090;
    };

    netbird-proxy-reporter = {host, ...}: host.meshAddress;

    # NetBird replaces auto-groups with the token's claim, so omitting netbird-users strips mesh access
    # on next login; gated apps add their groups the same way (_netbird-groups.nix).
    kanidm-provision = lib.recursiveUpdate (import ./_netbird-groups.nix "netbird-users") {
      groups.netbird-admin.members = ["lvdar"];

      # The client name is the audience management expects (cfg.oidc.clientId).
      oauth2.netbird = {
        displayName = "NetBird";
        public = true;
        # Fragment-free (kanidm#3217); keep in sync with AUTH_REDIRECT_URI and AUTH_SILENT_REDIRECT_URI below.
        originUrl = [
          "https://netbird.lvdar.nl/callback"
          "https://netbird.lvdar.nl/silent-callback"
          # netbird-proxy bearer auth (HttpConfig.AuthCallbackURL).
          "https://netbird.lvdar.nl/api/reverse-proxy/callback"
          # CLI PKCE ports; keep in sync with PKCEAuthorizationFlow.RedirectURLs below.
          "http://localhost:53000/"
          "http://localhost:54000/"
        ];
        originLanding = "https://netbird.lvdar.nl";

        claimMaps.groups = {
          joinType = "array";
          valuesByGroup.netbird-admin = ["netbird-admin"];
        };
      };
    };

    nixos = {
      config,
      lib,
      pkgs,
      netbird-service,
      ...
    }: let
      inherit (lib.options) mkOption mkEnableOption;
      inherit (lib.types) attrsOf bool enum listOf nullOr port str submodule;

      cfg = config.cosmos.services.netbird;

      mgmtPort = config.services.netbird.server.management.port;

      authority =
        "https://${cfg.domain}"
        + lib.optionalString (cfg.publicPort != 443) ":${toString cfg.publicPort}";

      # The reconciler only deletes services carrying this prefix; hand-made ones are untouched.
      managedPrefix = "nix-";

      policyPrefix = managedPrefix;
      fleetGroup = "${managedPrefix}fleet";
      resolverGroup = "${managedPrefix}resolvers";
      operatorGroup = "${managedPrefix}operators";
      callbackGroup = name: "${managedPrefix}callback-${name}";
      callbacks =
        lib.mapAttrsToList (name: c: {
          group = callbackGroup name;
          policy = "${policyPrefix}callback-${name}";
          inherit (c) protocol;
          inherit (c.ports) start end;
        })
        cfg.mesh.operatorCallbacks;

      # Same-host read: the fleet resolvers serve these names (gaia runs one).
      # attrByPath, as this module must not require the unbound aspect.
      meshOnlyNames = lib.attrNames (lib.attrByPath ["cosmos" "services" "unbound" "localRecords"] {} config);

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
            # Must nest under `auth`: the API silently drops a top-level
            # `bearer_auth`, publishing every service ungated.
            access_restrictions.crowdsec_mode = s.crowdsec;
            auth.bearer_auth = {
              enabled = s.bearerAuth.enable;
              distribution_groups = s.bearerAuth.groups;
            };
          })
          cfg.services
        )
      );

      # Bouncer key is minted by cscli at runtime on this host, so it is not in sops.
      crowdsecKeyFile = "/var/lib/netbird-proxy/crowdsec-bouncer.key";

      oidcPath = let
        m = builtins.match "https?://[^/]+(/.*)" cfg.oidc.configEndpoint;
      in
        if m == null
        then null
        else builtins.head m;

      # Names only what the SNI splitter routes to nginx, never the wildcard; see docs/src/networking.md#the-mesh-and-publishing.
      edgeCert = "netbird-edge";

      reconcile = pkgs.writeShellApplication {
        name = "netbird-reconcile-services";
        runtimeInputs = with pkgs; [curl jq];
        text = ''
          # Management's own listener: the public name would add DNS, TLS and the public port as failure points.
          api="http://127.0.0.1:${toString mgmtPort}/api"
          token="$(cat "$CREDENTIALS_DIRECTORY/api-token")"

          req() {
            curl -sSf \
              -H "Authorization: Token $token" \
              -H "Content-Type: application/json" \
              "$@"
          }

          # A refusal is benign only while the token is not yet a PAT (fresh install); a refused PAT must
          # exit non-zero so notify-failure alerts. Safe: this unit never runs during activation.
          body="$(mktemp)"
          trap 'rm -f "$body"' EXIT

          if ! code="$(curl -sS -o "$body" -w '%{http_code}' \
            -H "Authorization: Token $token" \
            -H "Content-Type: application/json" \
            "$api/peers")"; then
            code=000
          fi

          case "$code" in
            2*)
              peers="$(cat "$body")"
              ;;
            401 | 403)
              case "$token" in
                nbp_*)
                  echo "netbird: management refused the API token (HTTP $code)." >&2
                  echo "netbird: keys/netbird/api-token is invalid or expired. Nothing can be published until it is replaced — existing services keep working, so this does not show up as an outage." >&2
                  exit 1
                  ;;
                *)
                  echo "netbird: no API token yet; nothing to do"
                  exit 0
                  ;;
              esac
              ;;
            000)
              echo "netbird: management not reachable yet; nothing to do"
              exit 0
              ;;
            *)
              echo "netbird: management returned HTTP $code; nothing to do"
              exit 0
              ;;
          esac

          # JWT group sync is an account setting, off by default; without it every bearer check fails closed.
          # Merge into the current settings: a wholesale PUT resets network ranges and expiry policy.
          account="$(req "$api/accounts" | jq -r '.[0]')"
          account_id="$(jq -r .id <<<"$account")"
          # peer_approval_enabled keeps approving a user for a gated page from admitting their devices to the mesh.
          # See docs/src/notes/services-netbird.md#peer-approval.
          groups="$(req "$api/groups")"

          # peer_expose_enabled requires a non-empty peer_expose_groups; gating on All
          # (every peer) is no restriction.
          all_gid_for_expose="$(jq -r '.[] | select(.name == "All") | .id' <<<"$groups" | head -n1)"

          settings="$(jq --arg allid "$all_gid_for_expose" '.settings
            | .jwt_groups_enabled = true
            | .jwt_groups_claim_name = "groups"
            | .extra.peer_approval_enabled = true
            # Lets netbird expose publish straight from a peer CLI, outside cfg.services.
            | if $allid != "" then
                .peer_expose_enabled = true | .peer_expose_groups = [$allid]
              else . end' <<<"$account")"

          if [ -z "$all_gid_for_expose" ]; then
            echo "netbird: waiting on group All before enabling peer expose"
          fi

          if [ "$(jq -rS . <<<"$settings")" != "$(jq -rS .settings <<<"$account")" ]; then
            echo "netbird: updating account settings (JWT group sync, peer approval, peer expose)"
            req -X PUT -d "$(jq -n --argjson s "$settings" '{settings: $s}')" \
              "$api/accounts/$account_id" >/dev/null \
              || echo "netbird: WARNING could not update account settings"
          fi

          # Never create a distribution group: API-created groups stay issued=api, which JWT sync never fills,
          # so the gate admits nobody. A member's first login creates it; the next tick wires the service.
          unfillable="$(jq -r --argjson have "$groups" '
            [$have[] | select(.issued != "jwt") | .name] as $notjwt
            | [.[] | select(.auth.bearer_auth.enabled)
                   | .auth.bearer_auth.distribution_groups[]]
            | unique | map(select(. as $g | $notjwt | index($g))) | .[]' ${desiredFile})"

          if [ -n "$unfillable" ]; then
            while read -r name; do
              echo "netbird: WARNING group $name exists but was not issued by JWT sync;" \
                   "delete it and log in again, or nobody will ever match it"
            done <<<"$unfillable"
          fi

          ${lib.optionalString (cfg.mesh.fleet != []) ''
            # Mesh ACL; see docs/src/networking.md#the-mesh-and-publishing. These hold peers, not users, so creating
            # them is fine. Published services do not depend on them: netbird-proxy has its own per-service rules.
            ensure_group() {
              local gname="$1" want="$2" gid have
              gid="$(jq -r --arg n "$gname" \
                '.[] | select(.name == $n) | .id' <<<"$groups" | head -n1)"

              if [ -z "$gid" ]; then
                echo "netbird: creating peer group $gname"
                req -X POST -d "$(jq -n --arg n "$gname" --argjson p "$want" \
                  '{name: $n, peers: $p}')" "$api/groups" >/dev/null \
                  || echo "netbird: WARNING group $gname not created"
                groups="$(req "$api/groups")"
                return
              fi

              have="$(jq -c --arg n "$gname" \
                '[.[] | select(.name == $n) | .peers[]?.id] | sort' <<<"$groups")"
              if [ "$have" != "$(jq -cS . <<<"$want")" ]; then
                echo "netbird: updating peer group $gname"
                req -X PUT -d "$(jq -n --arg n "$gname" --argjson p "$want" \
                  '{name: $n, peers: $p}')" "$api/groups/$gid" >/dev/null \
                  || echo "netbird: WARNING group $gname not updated"
                groups="$(req "$api/groups")"
              fi
            }

            # Unresolved names are dropped, not fatal: a half-enrolled fleet must not lock out the rest.
            peer_ids() {
              jq -c --argjson peers "$peers" --argjson want "$1" \
                '[$peers[] | select(.name as $n | $want | index($n)) | .id] | sort' <<<'{}'
            }

            fleet_ids="$(peer_ids '${builtins.toJSON cfg.mesh.fleet}')"
            resolver_ids="$(peer_ids '${builtins.toJSON cfg.mesh.resolvers}')"
            operator_ids="$(peer_ids '${builtins.toJSON cfg.mesh.operators}')"

            if [ "$(jq 'length' <<<"$fleet_ids")" -eq 0 ]; then
              echo "netbird: no declared fleet peer exists yet; leaving mesh policy alone"
            else
              ensure_group ${fleetGroup} "$fleet_ids"
              ensure_group ${resolverGroup} "$resolver_ids"
              ${lib.optionalString (cfg.mesh.operators != []) ''ensure_group ${operatorGroup} "$operator_ids"''}
              ${lib.concatMapStrings (name: ''
              ensure_group ${callbackGroup name} "$(peer_ids '${builtins.toJSON cfg.mesh.operatorCallbacks.${name}.peers}')"
            '') (lib.attrNames cfg.mesh.operatorCallbacks)}

              gid() { jq -r --arg n "$1" '.[] | select(.name == $n) | .id' <<<"$groups" | head -n1; }
              fleet_gid="$(gid ${fleetGroup})"
              resolver_gid="$(gid ${resolverGroup})"
              operator_gid="$(gid ${operatorGroup})"
              all_gid="$(gid All)"

              # One rule per policy: NetBird silently keeps only a policy's first rule.
              # All keeps udp+tcp 53 to the resolvers, or peers outside the fleet resolve no mesh names.
              desired_policies="$(jq -n \
                --arg fleet "$fleet_gid" --arg resolver "$resolver_gid" --arg all "$all_gid" \
                --arg operator "${lib.optionalString (cfg.mesh.operators != []) "$operator_gid"}" \
                --argjson groups "$groups" --argjson callbacks '${builtins.toJSON callbacks}' \
                '[
                  { name: "${policyPrefix}fleet",
                    description: "The fleet'"'"'s own machines, freely",
                    enabled: true,
                    rules: [{ name: "${policyPrefix}fleet", enabled: true, action: "accept",
                              bidirectional: true, protocol: "all",
                              sources: [$fleet], destinations: [$fleet] }] },
                  { name: "${policyPrefix}dns-udp",
                    description: "Every peer may resolve names",
                    enabled: true,
                    rules: [{ name: "${policyPrefix}dns-udp", enabled: true, action: "accept",
                              bidirectional: false, protocol: "udp", ports: ["53"],
                              sources: [$all], destinations: [$resolver] }] },
                  { name: "${policyPrefix}dns-tcp",
                    description: "Every peer may resolve names, over tcp too",
                    enabled: true,
                    rules: [{ name: "${policyPrefix}dns-tcp", enabled: true, action: "accept",
                              bidirectional: false, protocol: "tcp", ports: ["53"],
                              sources: [$all], destinations: [$resolver] }] }
                ]
                + if $operator == "" then [] else [
                  { name: "${policyPrefix}operators",
                    description: "Operator devices into the fleet, not back",
                    enabled: true,
                    rules: [{ name: "${policyPrefix}operators", enabled: true, action: "accept",
                              bidirectional: false, protocol: "all",
                              sources: [$operator], destinations: [$fleet] }] }
                ] + [$callbacks[] as $c
                  | ($groups[] | select(.name == $c.group) | .id) as $src
                  | { name: $c.policy,
                      description: "Fleet peers back to operator devices, \($c.protocol) \($c.start)-\($c.end)",
                      enabled: true,
                      rules: [{ name: $c.policy, enabled: true, action: "accept",
                                bidirectional: false, protocol: $c.protocol,
                                port_ranges: [{ start: $c.start, end: $c.end }],
                                sources: [$src], destinations: [$operator] }] }
                ] end')"

              existing_policies="$(req "$api/policies")"

              jq -c '.[]' <<<"$desired_policies" | while read -r pol; do
                pname="$(jq -r .name <<<"$pol")"
                pid="$(jq -r --arg n "$pname" \
                  '.[] | select(.name == $n) | .id' <<<"$existing_policies" | head -n1)"

                if [ -z "$pid" ]; then
                  echo "netbird: creating policy $pname"
                  req -X POST -d "$pol" "$api/policies" >/dev/null \
                    || echo "netbird: WARNING policy $pname not created"
                else
                  # Compare only declared fields: the API echoes groups, counts and ids, which would rewrite every tick.
                  current="$(jq -c --arg n "$pname" '.[] | select(.name == $n)
                    | {name, description, enabled,
                       rules: [.rules[] | {name, enabled, action, bidirectional,
                                           protocol, ports, port_ranges,
                                           sources: [.sources[].id],
                                           destinations: [.destinations[].id]}]}' \
                    <<<"$existing_policies")"
                  want="$(jq -cS '{name, description, enabled,
                    rules: [.rules[] | {name, enabled, action, bidirectional,
                                        protocol, ports: (.ports // null),
                                        port_ranges: (.port_ranges // null),
                                        sources, destinations}]}' <<<"$pol")"
                  if [ "$(jq -cS . <<<"$current")" != "$want" ]; then
                    echo "netbird: updating policy $pname"
                    req -X PUT -d "$pol" "$api/policies/$pid" >/dev/null \
                      || echo "netbird: WARNING policy $pname not updated"
                  fi
                fi
              done

              # Prune prefixed policies no longer declared: a renamed allow-list policy would otherwise
              # keep enforcing a grant nobody declares.
              jq -r --arg p '${policyPrefix}' --argjson d "$desired_policies" '
                [$d[].name] as $declared
                | .[]
                | select(.name | startswith($p))
                | select(.name | IN($declared[]) | not)
                | "\(.id) \(.name)"' <<<"$existing_policies" |
              while read -r id name; do
                echo "netbird: removing policy $name"
                req -X DELETE "$api/policies/$id" >/dev/null \
                  || echo "netbird: WARNING policy $name not removed"
              done

              ${
              if cfg.mesh.enforce
              then ''
                # Disabled, not deleted: re-enabling it in the dashboard is the rebuild-free way back (see mesh.enforce).
                default_id="$(jq -r '.[] | select(.name == "Default" and .enabled) | .id' \
                  <<<"$existing_policies" | head -n1)"
                if [ -n "$default_id" ]; then
                  echo "netbird: disabling the built-in All -> All policy"
                  req -X PUT -d "$(jq -c --arg id "$default_id" \
                    '.[] | select(.id == $id)
                     | .enabled = false
                     | .rules |= map(.enabled = false)
                     | {name, description, enabled,
                        rules: [.rules[] | {name, description, enabled, action,
                                            bidirectional, protocol,
                                            sources: [.sources[].id],
                                            destinations: [.destinations[].id]}]}' \
                    <<<"$existing_policies")" "$api/policies/$default_id" >/dev/null \
                    || echo "netbird: WARNING could not disable the Default policy"
                fi
              ''
              else ''
                echo "netbird: mesh policies present; All -> All still enabled" \
                     "(set cosmos.services.netbird.mesh.enforce to cut over)"
              ''
            }
            fi
          ''}

          # Management's half of NetBird's own SSH server (not OpenSSH); see sshPeers. The PUT replaces
          # the peer, so expiry and approval fields are carried as they are or they reset.
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

          # Mesh domain plus mesh-only names, never primary: primary makes all DNS fail wherever the mesh does.
          # See docs/src/notes/services-netbird.md#mesh-dns-scope.
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
                --arg peers "${lib.concatStringsSep ", " cfg.dnsPeers}" \
                --argjson meshOnly ${lib.escapeShellArg (builtins.toJSON meshOnlyNames)} \
                --arg domain ${lib.escapeShellArg cfg.dnsDomain} '{
                  name: $name,
                  description: ("unbound on " + $peers),
                  nameservers: [$ips[] | {ip: ., ns_type: "udp", port: 53}],
                  enabled: true,
                  groups: [$group],
                  primary: false,
                  domains: ([$domain] + $meshOnly),
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

          annotated="$(jq \
            --argjson peers "$peers" \
            --argjson groups "$groups" '
            def peer_id($n): ([$peers[] | select(.name == $n) | .id] | first);
            # jwt-issued only: an api-issued group never gains a member (see the unfillable check).
            def group_id($n):
              ([$groups[] | select(.name == $n and .issued == "jwt") | .id] | first);

            map(
              .targets |= map(.target_id = peer_id(.peer))
              | .auth.bearer_auth.distribution_groups |= map({name: ., id: group_id(.)})
            )' ${desiredFile})"

          # Unresolved names warn, not fail: a missing peer holds the service back, a missing group is left out of the gate.
          jq -r '
            .[] | select(any(.targets[]; .target_id == null))
            | "netbird: \(.name) waiting on " + (
                [.targets[] | select(.target_id == null) | "peer " + .peer]
                | join(", ")
              )' <<<"$annotated"

          jq -r '
            .[] | select(.auth.bearer_auth.enabled
                         and any(.auth.bearer_auth.distribution_groups[]; .id == null))
            | "netbird: \(.name) gate omits " + (
                [.auth.bearer_auth.distribution_groups[] | select(.id == null) | .name]
                | join(", ")
              ) + " — no such jwt-issued group yet"' <<<"$annotated"

          # `any`, not `all`: an absent group has no members, so publishing with the resolved ones admits the same
          # people without freezing unrelated changes. None resolving is a skip: an empty list is not a narrower gate.
          desired="$(jq '
            [.[] | select(
              (all(.targets[]; .target_id != null))
              and ((.auth.bearer_auth.enabled | not)
                   or any(.auth.bearer_auth.distribution_groups[]; .id != null))
            )]
            | map(
              .targets |= map(del(.peer))
              | .auth.bearer_auth.distribution_groups |=
                  (map(select(.id != null) | .id))
            )' <<<"$annotated")"

          echo "$desired" | jq -c '.[]' | while read -r svc; do
            name="$(jq -r .name <<<"$svc")"
            id="$(jq -r --arg n "$name" \
              '.[] | select(.name == $n) | .id' <<<"$existing" | head -n1)"

            # Warn and continue per service: a 409 (domain owned by a hand-made service) must not stop the rest.
            if [ -n "$id" ]; then
              # PUT only on a real difference: each PUT re-provisions the service (certificate, IdP discovery fetch).
              # Both sides share one normaliser: the API adds per-target fields and reports an unset listen_port as 0.
              norm='def n: {
                  name, domain, mode, enabled,
                  listen_port: (.listen_port // 0),
                  pass_host_header: (.pass_host_header // false),
                  crowdsec: (.access_restrictions.crowdsec_mode // "off"),
                  bearer_enabled: (.auth.bearer_auth.enabled // false),
                  # Only meaningful when gated: with bearer auth off the API stores [""].
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
                || echo "netbird: WARNING $name not created — domain or listen port already taken; if a rename is in flight this clears on the next tick"
            fi
          done

          # Prune only prefixed services no longer declared, against $annotated, not $desired:
          # a declared service whose peer is offline must not be deleted.
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

      # Warn before the PAT lapses: once expired, publishing is already frozen.
      tokenExpiry = pkgs.writeShellApplication {
        name = "netbird-token-expiry";
        runtimeInputs = with pkgs; [curl jq coreutils];
        text = ''
          api="http://127.0.0.1:${toString mgmtPort}/api"
          token="$(cat "$CREDENTIALS_DIRECTORY/api-token")"

          req() {
            curl -sSf \
              -H "Authorization: Token $token" \
              -H "Content-Type: application/json" \
              "$@"
          }

          # Unreachable management or a refused token is reported by netbird-services; one fault, one alert.
          if ! users="$(req "$api/users" 2>/dev/null)"; then
            echo "netbird: management not reachable or token refused; expiry not checked"
            exit 0
          fi

          uid="$(jq -r 'map(select(.is_current == true)) | .[0].id // empty' <<<"$users")"
          if [ -z "$uid" ]; then
            echo "netbird: no is_current user in /users; cannot tell which account this token belongs to"
            exit 0
          fi

          tokens="$(req "$api/users/$uid/tokens")"

          # Ours is the most recently used PAT (this script just used it); worst case warns about a sibling token.
          latest="$(jq -r 'sort_by(.last_used) | last' <<<"$tokens")"
          exp="$(jq -r '.expiration_date // empty' <<<"$latest")"
          name="$(jq -r '.name // "?"' <<<"$latest")"

          if [ -z "$exp" ]; then
            echo "netbird: token '$name' carries no expiration_date; nothing to warn about"
            exit 0
          fi

          # Management emits nanosecond precision, which GNU date will not parse.
          exp_clean="$(sed -E 's/\.[0-9]+//' <<<"$exp")"
          days=$(( ( $(date -d "$exp_clean" +%s) - $(date +%s) ) / 86400 ))

          if [ "$days" -lt 0 ]; then
            echo "netbird: API token '$name' EXPIRED $(( -days )) day(s) ago ($exp_clean)." >&2
            exit 1
          fi

          if [ "$days" -le ${toString cfg.tokenExpiryWarnDays} ]; then
            echo "netbird: API token '$name' expires in $days day(s), on $exp_clean." >&2
            echo "netbird: mint a replacement and put it in keys/netbird/api-token. Once it lapses nothing new can be published while everything already published keeps working — so there is no outage to notice." >&2
            exit 1
          fi

          echo "netbird: API token '$name' expires in $days day(s); nothing to do"
        '';
      };

      proxyAddressDir = "/var/lib/netbird-proxy-address";

      reportProxyAddress = pkgs.writeShellApplication {
        name = "netbird-proxy-address";
        runtimeInputs = with pkgs; [sqlite coreutils];
        text = ''
          # Embedded proxy peers are hidden from the API. Newest session wins: a dead proxy's
          # ephemeral peer can stay marked connected indefinitely.
          addr="$(sqlite3 -readonly -cmd '.timeout 10000' \
            'file:/var/lib/netbird-mgmt/data/store.db?mode=ro' \
            "SELECT trim(ip, '\"') FROM peers
             WHERE proxy_meta_embedded = 1 AND proxy_meta_cluster = '${cfg.baseDomain}' AND peer_status_connected = 1
             ORDER BY peer_status_session_started_at DESC LIMIT 1")"

          cd ${proxyAddressDir}
          if [[ -z $addr ]]; then
            echo "no connected netbird-proxy peer"
            rm -f proxy.prom
            exit 0
          fi

          printf '# HELP netbird_proxy_peer_info The mesh address netbird-proxy dials upstreams from.\n# TYPE netbird_proxy_peer_info gauge\nnetbird_proxy_peer_info{address="%s"} 1\n' "$addr" >proxy.prom.tmp
          mv proxy.prom.tmp proxy.prom
        '';
      };
    in {
      options.cosmos.services.netbird = {
        tokenExpiryWarnDays = mkOption {
          type = lib.types.ints.positive;
          default = 21;
          description = ''
            Start warning this many days before the management API token
            expires.

            Wide on purpose. Replacing it means minting a PAT by hand in the
            dashboard, editing sops and moving the flake pin, which is not a
            thing to be told about the evening it stops working.
          '';
        };

        baseDomain = mkOption {
          type = str;
          default = "lvdar.nl";
          description = ''
            Cluster domain of the reverse proxy. Every published service is a
            subdomain of it, which works without registering custom domains
            because `*.lvdar.nl` already resolves to this host.
          '';
        };

        localVhosts = mkOption {
          type = attrsOf (submodule {
            options.upstream = mkOption {
              type = str;
              example = "http://100.68.151.172:3031";
              description = ''
                Where to forward, as a mesh address. A literal, for the same
                reason every other target here is one: den cannot read another
                host's config.
              '';
            };
          });
          default = {};
          description = ''
            Domains this host's nginx serves itself, instead of handing them to
            netbird-proxy.

            The reason this exists is a hard limit in the proxy rather than a
            preference: its cluster domain *is* baseDomain, and the management
            API rejects any service whose domain is not a label beneath it —
            `domain lvdar.nl requires a subdomain label`, HTTP 422. So the apex
            cannot be published through the proxy at all, however it is spelled.

            The cost of coming in this way is that CrowdSec and the NetBird
            identity gate are both bypassed, because the request never reaches
            the proxy that implements them. Only put a domain here that is meant
            to be entirely public, and note that services/gatus.nix probing it
            is then the only thing watching it.

            oidc.idp is the same mechanism with a different justification (a
            bootstrap deadlock rather than a naming rule) and predates this.
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

          # Not through netbird-proxy: management exits without discovery, and the proxy needs management.
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
            activation. Peers and groups are given by name, not id. This is
            the only internet-reachable surface. Apps publish their entries
            on the `netbird-service` quirk from their own aspect.
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

        mesh = {
          fleet = mkOption {
            type = listOf str;
            default = [];
            example = ["endeavour" "gaia" "pioneer" "voyager"];
            description = ''
              Peers, by name, that may reach each other on the mesh without
              restriction — the fleet's own machines.

              Empty leaves mesh policy untouched, which is NetBird's default of
              one All -> All rule covering every peer in both directions. That
              is not really a default: it means any peer anybody enrols reaches
              every port on every host, including services with no
              authentication of their own.

              Published services do not depend on this. netbird-proxy holds its
              own per-service ACL rule for each, so scoping this affects
              machine-to-machine traffic and nothing a browser does.

              A name that matches no peer is skipped, and if none match the
              policy is left alone entirely — a half-enrolled fleet must not
              produce a rule that locks out the rest of it.
            '';
          };

          resolvers = mkOption {
            type = listOf str;
            default = [];
            example = ["endeavour" "gaia"];
            description = ''
              Peers running the mesh nameservers. Every peer keeps udp/tcp 53 to
              these, fleet or not.

              Not optional in practice: the nameserver group is primary for All,
              so a peer that cannot reach :53 resolves nothing whatsoever. That
              is an outage rather than a boundary, and it would land on phones
              first. Keep in step with the resolver addresses this aspect hands
              out.
            '';
          };

          operators = mkOption {
            type = listOf str;
            default = [];
            example = ["panther"];
            description = ''
              Non-fleet peers, by name, that may open connections to every fleet
              host on any port, while the fleet cannot open any back to them. For
              a phone that administers the fleet over SSH: as a fleet member it
              would be reachable from every host, and as a plain peer it gets
              DNS and nothing else. That includes mesh-only names, which then
              resolve but never connect.

              A mesh grant only, not a login: sshd still wants a key from
              core/_ssh-keys/authorized.nix.
            '';
          };

          operatorCallbacks = mkOption {
            type = attrsOf (submodule {
              options = {
                peers = mkOption {
                  type = listOf str;
                  example = ["voyager"];
                  description = "Fleet peers, by name, that may open connections to the operators.";
                };
                protocol = mkOption {
                  type = enum ["tcp" "udp"];
                  description = "Protocol the callback uses.";
                };
                ports = {
                  start = mkOption {
                    type = port;
                    description = "First port of the range on the operator.";
                  };
                  end = mkOption {
                    type = port;
                    description = "Last port of the range on the operator.";
                  };
                };
              };
            });
            default = {};
            example = {
              kde-connect = {
                peers = ["voyager"];
                protocol = "tcp";
                ports = {
                  start = 1714;
                  end = 1764;
                };
              };
            };
            description = ''
              Narrow exceptions to `operators` being unreachable: each entry
              lets its fleet peers open connections to every operator on one
              protocol and port range. For apps whose protocol has the receiving
              side dial back, such as KDE Connect, where the peer that hears the
              phone's UDP identity opens the TCP link to it.

              Ignored while `operators` is empty.
            '';
          };

          enforce = mkOption {
            type = bool;
            default = false;
            description = ''
              Disable NetBird's built-in All -> All policy, leaving the ones
              built from `fleet`, `resolvers` and `operators` as the whole of mesh access.

              Separate from creating those policies on purpose. Deploy once with
              this off, confirm the new rules have appeared in
              `nft list chain ip netbird netbird-acl-input-rules` on a couple of
              hosts, and only then turn it on — the failure this guards against
              is losing SSH to the entire fleet simultaneously, and every host
              here is reached over the mesh.

              The policy is disabled rather than deleted, so re-enabling it in
              the dashboard is the way back and needs no rebuild.
            '';
          };
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
        cosmos.services.netbird.services = lib.mkMerge netbird-service;

        sops.secrets = {
          # coturn's preStart reads this as the service user; root-only gives EACCES.
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
          # The bootstrap cache must survive the root wipe.
          ++ lib.optional (cfg.oidc.idp.domain != null && oidcPath != null) {
            directory = "/var/cache/nginx";
            user = "nginx";
            group = "nginx";
            mode = "0700";
          };

        # Management exits if OIDC discovery fails; unlimited restarts keep it out of
        # the rate limiter, so activation does not fail and deploy-rs not roll back.
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

              # Module default is a placeholder that warns; this flake aborts on warn.
              TURNConfig.Secret._secret =
                config.sops.secrets."keys/netbird/turn-secret".path;

              # Both the SNI splitter and the proxy sit in front, and both speak
              # PROXY protocol, so the only trustworthy hop is loopback.
              ReverseProxy = {
                TrustedHTTPProxies = ["127.0.0.1/32"];
                TrustedHTTPProxiesCount = 1;
              };

              # Endpoints unset on purpose: filled from the discovery document.
              PKCEAuthorizationFlow.ProviderConfig = {
                Audience = cfg.oidc.clientId;
                ClientID = cfg.oidc.clientId;

                # Loopback only (the CLI flow): a port-less dashboard URL here hijacks the CLI's code.
                # Keep in sync with the localhost entries in oauth2.netbird.originUrl above.
                RedirectURLs = [
                  "http://localhost:53000"
                  "http://localhost:54000"
                ];
              };

              # The module hardcodes :443 here; peers dial whatever the splitter
              # actually listens on.
              Signal.URI = "${cfg.domain}:${toString cfg.publicPort}";

              # The audience cannot be derived outside the embedded IdP; left empty,
              # every API call is rejected (eternal dashboard spinner).
              HttpConfig = {
                AuthAudience = cfg.oidc.clientId;
                AuthClientID = cfg.oidc.clientId;
                # Only defaulted alongside the embedded IdP.
                AuthUserIDClaim = "sub";

                # Unset, the IdP rejects bearer-auth logins (no redirect_uri).
                # Only defaulted alongside the embedded IdP.
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

              # kanidm strips fragments (kanidm#3217), so `/#callback` never matches; these must not be
              # dashboard pages. Keep in sync with oauth2.netbird.originUrl above.
              AUTH_REDIRECT_URI = "/callback";
              AUTH_SILENT_REDIRECT_URI = "/silent-callback";
            };
          };
        };

        security.acme.certs.${edgeCert} = {
          inherit (cfg) domain;
          extraDomainNames =
            lib.optional (cfg.oidc.idp.domain != null) cfg.oidc.idp.domain
            ++ lib.attrNames cfg.localVhosts;
        };

        # Loopback-only; the SNI splitter owns the public socket.
        services.nginx.virtualHosts =
          {
            # Last resort for a Host this listener does not serve; edgeCert
            # keeps browsers from coalescing other domains onto it.
            "_" = {
              default = true;
              onlySSL = true;
              useACMEHost = edgeCert;
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
              useACMEHost = edgeCert;
              listen = [
                {
                  addr = "127.0.0.1";
                  port = cfg.localTlsPort;
                  ssl = true;
                  proxyProtocol = true;
                }
              ];
              # Callback paths are not exported; serve the 404 page (same
              # OidcProvider layout) as a 200.
              locations = lib.genAttrs ["= /callback" "= /silent-callback"] (_: {
                extraConfig = "try_files /404.html =404;";
              });

              extraConfig = ''
                set_real_ip_from 127.0.0.1;
                real_ip_header proxy_protocol;
              '';
            };
          }
          # proxy_ssl_verify off: the peer's cert cannot match the mesh address;
          # the hop is inside WireGuard.
          // lib.optionalAttrs (cfg.oidc.idp.domain != null) {
            ${cfg.oidc.idp.domain} = {
              onlySSL = true;
              useACMEHost = edgeCert;
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
                  # Management needs this document over the mesh it brings up; serve it stale from cache.
                  # See docs/src/restore.md#the-cold-start-deadlock.
                  "= ${oidcPath}" = {
                    proxyPass = "${cfg.oidc.idp.upstream}${oidcPath}";
                    extraConfig = ''
                      proxy_ssl_verify off;
                      proxy_cache oidc_bootstrap;
                      # kanidm sends no-store, which nginx honours by caching nothing. Ignoring it is safe only
                      # here: the discovery document is public metadata with no session or token material.
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
          }
          # Domains the proxy cannot carry (see localVhosts); plain HTTP inside WireGuard.
          // lib.mapAttrs (_: vhost: {
            onlySSL = true;
            useACMEHost = edgeCert;
            listen = [
              {
                addr = "127.0.0.1";
                port = cfg.localTlsPort;
                ssl = true;
                proxyProtocol = true;
              }
            ];
            locations."/" = {
              proxyPass = vhost.upstream;
              proxyWebsockets = true;
            };
            extraConfig = ''
              set_real_ip_from 127.0.0.1;
              real_ip_header proxy_protocol;
            '';
          })
          cfg.localVhosts;

        # inactive=365d so the entry survives an IdP outage of any length.
        services.nginx.appendHttpConfig = lib.mkIf (cfg.oidc.idp.domain != null && oidcPath != null) ''
          proxy_cache_path /var/cache/nginx/oidc-bootstrap
            levels=1:2 keys_zone=oidc_bootstrap:1m max_size=1m
            inactive=365d use_temp_path=off;
        '';

        # Must not terminate: netbird-proxy answers ACME tls-alpn-01 on this socket.
        services.nginx.streamConfig = ''
          map $ssl_preread_server_name $netbird_upstream {
            ${cfg.domain}  127.0.0.1:${toString cfg.localTlsPort};
            ${lib.optionalString (cfg.oidc.idp.domain != null)
            "${cfg.oidc.idp.domain}  127.0.0.1:${toString cfg.localTlsPort};"}
            ${lib.concatStringsSep "\n            " (lib.mapAttrsToList (
              domain: _: "${domain}  127.0.0.1:${toString cfg.localTlsPort};"
            )
            cfg.localVhosts)}
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

        # L4 services bypass the SNI split and hit netbird-proxy directly.
        networking.firewall = let
          l4 = lib.filter (p: p != null) (lib.mapAttrsToList (_: s: s.listenPort) cfg.services);
        in {
          allowedTCPPorts = [cfg.publicPort] ++ l4;
          allowedUDPPorts =
            lib.mapAttrsToList (_: s: s.listenPort)
            (lib.filterAttrs (_: s: s.mode == "udp" && s.listenPort != null) cfg.services);
        };

        # Idempotent, so a wiped crowdsec database is re-populated without
        # invalidating the key.
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

        # nixpkgs ships no module for netbird-proxy.
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
              # Default /var/lib/netbird is unwritable under ProtectSystem=strict
              # and belongs to the agent; two daemons must not share state.json.
              NB_STATE_DIR = "/var/lib/netbird-proxy";
              # Otherwise every client IP reads as 127.0.0.1.
              NB_PROXY_PROXY_PROTOCOL = "true";
              NB_PROXY_TRUSTED_PROXIES = "127.0.0.1/32,::1/128";
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
            # NET_BIND_SERVICE for L4 services below 1024; without it the proxy silently never binds.
            AmbientCapabilities = ["CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE"];
            CapabilityBoundingSet = ["CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE"];

            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            RestrictSUIDSGID = true;
          };

          script = ''
            export NB_PROXY_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/token")"
            ${lib.optionalString config.services.crowdsec.enable ''
              export NB_PROXY_CROWDSEC_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/crowdsec-key")"
            ''}
            exec ${lib.getExe pkgs.netbird-proxy}
          '';
        };

        # NoNewPrivileges unit: no exec transitions out of this profile.
        security.apparmor.policies.netbird-proxy = {
          inherit (config.cosmos.security.apparmor) state;
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile netbird-proxy ${lib.getExe pkgs.netbird-proxy} flags=(attach_disconnected,mediate_deleted) {
              include <abstractions/base-strict>
              include <abstractions/nameservice>
              include <abstractions/ssl_certs>

              capability net_admin,
              capability net_bind_service,

              network inet stream,
              network inet6 stream,
              network inet dgram,
              network inet6 dgram,
              network netlink raw,

              ${lib.getExe pkgs.netbird-proxy} mr,

              /var/lib/netbird-proxy/ rw,
              /var/lib/netbird-proxy/** rwkl,
              /tmp/ r,
              owner /tmp/** rwk,

              @{PROC}/sys/net/core/somaxconn r,
              owner @{PROC}/@{pid}/{stat,status,limits,cgroup,mountinfo} r,
              owner @{PROC}/@{pid}/net/** r,
              @{sys}/class/net/ r,
              @{sys}/devices/**/net/** r,
              @{sys}/fs/cgroup/** r,
              /dev/net/tun rw,

              deny capability dac_override,
              deny capability dac_read_search,
              deny capability sys_admin,
              deny capability sys_ptrace,
              deny /run/credentials/** rwlkmx,
              deny /run/secrets{,.d}/** rwlkmx,
              deny /run/secrets-for-users{,.d}/** rwlkmx,
              deny /persist/** rwlkmx,
              deny /var/lib/{netbird,netbird-mgmt,acme,stalwart,crowdsec,bulwark,gatus,private}/** rwlkmx,
              deny /etc/ssh/ssh_host_* rwlkmx,

              include if exists <local/netbird-proxy>
            }
          '';
        };

        # Timer-driven, NOT multi-user.target: it cannot succeed before peers
        # enrol and a real token exists, and an activation failure makes deploy-rs roll back.
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

        systemd.services.netbird-token-expiry = {
          description = "Warn before the NetBird API token expires";
          after = ["netbird-management.service"];
          wants = ["netbird-management.service"];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe tokenExpiry;
            LoadCredential = [
              "api-token:${config.sops.secrets."keys/netbird/api-token".path}"
            ];
          };
        };

        systemd.timers.netbird-token-expiry = {
          description = "Periodically check the NetBird API token's expiry";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "daily";
            RandomizedDelaySec = "1h";
            Persistent = true;
            Unit = "netbird-token-expiry.service";
          };
        };

        services.prometheus.exporters.node.extraFlags = ["--collector.textfile.directory=${proxyAddressDir}"];

        systemd.services.netbird-proxy-address = {
          description = "Export netbird-proxy's mesh address for the hosts it targets";
          after = ["netbird-management.service"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe reportProxyAddress;
            StateDirectory = "netbird-proxy-address";
            StateDirectoryMode = "0755";

            CapabilityBoundingSet = [""];
            NoNewPrivileges = true;
            PrivateNetwork = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
          };
        };

        # Timer-driven: the proxy peer appears only once management is up and the proxy has enrolled.
        systemd.timers.netbird-proxy-address = {
          description = "Periodic netbird-proxy address export";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitActiveSec = "1min";
            Unit = "netbird-proxy-address.service";
          };
        };
      };
    };
  };
}
