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
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) enum listOf port str;

    cfg = config.cosmos.services.netbird;

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
        # TRANSITIONAL. Every host has to agree on this, and den gives an aspect
        # no way to read another host's config, so it is a shared default rather
        # than a per-host setting: one line to flip at the cutover.
        default = 9443;
        description = ''
          Public port the control plane answers on. Clients embed it in their
          management URL, so server and clients must agree — which is why it
          lives here rather than in the server-only options.

          It exists because Pangolin's traefik already owns :443 on gaia, and
          the two have to coexist until the cutover. Set it to a spare port
          while both are running, then move it back to 443 when Pangolin goes.

          netbird-proxy's ACME uses tls-alpn-01, which is only answerable on
          443, so publishing services genuinely requires the default. During
          the transition the mesh works and the dashboard is reachable on the
          alternate port; only the reverse proxy has to wait.
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
          '';
        };
      };
    };

    config = {
      sops.secrets."keys/netbird/setup-key" = {};

      networking.firewall.interfaces.${config.services.netbird.clients.default.interface} = {
        allowedTCPPorts = cfg.client.exposedPorts;
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

          # Enrolls unattended with a setup key. Deliberately not the
          # interactive OIDC flow: that would need kanidm reachable *before*
          # the host is on the mesh, and kanidm is published through it.
          login = {
            enable = true;
            setupKeyFile = config.sops.secrets."keys/netbird/setup-key".path;
            systemdDependencies = ["sops-install-secrets.service"];
          };

          # The login unit runs a bare `netbird up`, so the self-hosted
          # management URL has to already be in config.json. That is what the
          # module's `config` drop-in is for.
          config = {
            ManagementURL = urlValue cfg.domain;
            AdminURL = urlValue cfg.domain;
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

      service = submodule ({name, ...}: {
        options = {
          domain = mkOption {
            type = str;
            default = "${name}.${cfg.baseDomain}";
            defaultText = "<name>.\${baseDomain}";
          };
          mode = mkOption {
            type = enum ["http" "tcp" "udp" "tls"];
            default = "http";
          };
          enabled = mkOption {
            type = bool;
            default = true;
          };
          targets = mkOption {type = listOf target;};
          bearerAuth = {
            enable =
              mkEnableOption "a NetBird identity check in front of this service"
              // {default = true;};
            groups = mkOption {
              type = listOf str;
              default = ["All"];
              description = ''
                NetBird group names allowed through. Resolved to ids at
                activation time, same as peers. "All" is created by NetBird
                itself, so the default gates on "any authenticated user".
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
            targets = map (t:
              {
                inherit (t) peer port protocol;
                target_type = "peer";
                enabled = true;
              }
              // lib.optionalAttrs (t.path != null) {inherit (t) path;})
            s.targets;
            bearer_auth = {
              enabled = s.bearerAuth.enable;
              distribution_groups = s.bearerAuth.groups;
            };
          })
          cfg.services
        )
      );

      reconcile = pkgs.writeShellApplication {
        name = "netbird-reconcile-services";
        runtimeInputs = with pkgs; [curl jq];
        text = ''
          api="https://${cfg.domain}/api"
          token="$(cat "$CREDENTIALS_DIRECTORY/api-token")"

          req() {
            curl -sSf \
              -H "Authorization: Token $token" \
              -H "Content-Type: application/json" \
              "$@"
          }

          peers="$(req "$api/peers")"
          groups="$(req "$api/groups")"
          existing="$(req "$api/reverse-proxies/services")"

          # Swap peer and group names for the ids the API wants. A name that
          # matches nothing is fatal on purpose: posting a service with a null
          # target would leave it published but broken.
          desired="$(jq \
            --argjson peers "$peers" \
            --argjson groups "$groups" '
            def peer_id($n):
              ([$peers[] | select(.name == $n) | .id] | first)
              // error("no netbird peer named \($n) — has it enrolled yet?");
            def group_id($n):
              ([$groups[] | select(.name == $n) | .id] | first)
              // error("no netbird group named \($n)");

            map(
              .targets |= map(.target_id = peer_id(.peer) | del(.peer))
              | .bearer_auth.distribution_groups |= map(group_id(.))
            )' ${desiredFile})"

          echo "$desired" | jq -c '.[]' | while read -r svc; do
            name="$(jq -r .name <<<"$svc")"
            id="$(jq -r --arg n "$name" \
              '.[] | select(.name == $n) | .id' <<<"$existing" | head -n1)"

            if [ -n "$id" ]; then
              echo "netbird: updating $name"
              req -X PUT -d "$svc" "$api/reverse-proxies/services/$id" >/dev/null
            else
              echo "netbird: creating $name"
              req -X POST -d "$svc" "$api/reverse-proxies/services" >/dev/null
            fi
          done

          # Prune only what we own: anything carrying the managed prefix that is
          # no longer declared. Services made by hand are left alone.
          jq -r --arg p '${managedPrefix}' --argjson d "$desired" '
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
          default = 8443;
          description = "Loopback port netbird-proxy listens on, behind the SNI splitter.";
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
        };

        services = mkOption {
          type = attrsOf service;
          default = {};
          description = ''
            Reverse-proxy services, reconciled against the management API on
            activation. Peers and groups are given by name, not id.
          '';
        };
      };

      config = {
        sops.secrets = {
          "keys/netbird/coturn-password" = {};
          "keys/netbird/turn-secret" = {};
          "keys/netbird/datastore-encryption-key" = {};
          "keys/netbird/proxy-token" = {};
          "keys/netbird/api-token" = {};
        };

        cosmos.system.impermanence.persist.directories = [
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
        ];

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
                RedirectURLs = [
                  "${authority}/peers"
                  "http://localhost:53000"
                ];
              };

              # The module hardcodes :443 here; peers dial whatever the splitter
              # actually listens on.
              Signal.URI = "${cfg.domain}:${toString cfg.publicPort}";
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
            };
          };
        };

        # The netbird modules contribute locations to this vhost but no listener
        # and no TLS, which is left to us. It is deliberately loopback-only: the
        # SNI splitter below owns the public socket.
        services.nginx.virtualHosts.${cfg.domain} = {
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
          extraConfig = ''
            set_real_ip_from 127.0.0.1;
            real_ip_header proxy_protocol;
          '';
        };

        # Split the public port by SNI without terminating. netbird-proxy
        # answers ACME tls-alpn-01 challenges on this socket, so decrypting
        # here would break its certificate renewal.
        services.nginx.streamConfig = ''
          map $ssl_preread_server_name $netbird_upstream {
            ${cfg.domain}  127.0.0.1:${toString cfg.localTlsPort};
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

        networking.firewall.allowedTCPPorts = [cfg.publicPort];

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

          environment = {
            NB_PROXY_DOMAIN = cfg.baseDomain;
            NB_PROXY_ADDRESS = ":${toString cfg.proxyPort}";
            NB_PROXY_MANAGEMENT_ADDRESS = "http://127.0.0.1:${toString mgmtPort}";
            NB_PROXY_ALLOW_INSECURE = "true";
            NB_PROXY_ACME_CERTIFICATES = "true";
            NB_PROXY_ACME_CHALLENGE_TYPE = "tls-alpn-01";
            NB_PROXY_CERTIFICATE_DIRECTORY = "/var/lib/netbird-proxy/certs";
            NB_PROXY_GEO_DATA_DIR = "/var/lib/netbird-proxy/geolocation";
            # Client IPs would otherwise all read as 127.0.0.1, which would make
            # any CIDR or country restriction meaningless.
            NB_PROXY_PROXY_PROTOCOL = "true";
            NB_PROXY_TRUSTED_PROXIES = "127.0.0.1/32,::1/128";
            # Services live at <name>.lvdar.nl, never at the bare domain.
            NB_PROXY_REQUIRE_SUBDOMAIN = "true";
          };

          serviceConfig = {
            LoadCredential = [
              "token:${config.sops.secrets."keys/netbird/proxy-token".path}"
            ];
            Restart = "always";
            RestartSec = "5s";
            StateDirectory = "netbird-proxy";
            StateDirectoryMode = "0750";
            WorkingDirectory = "/var/lib/netbird-proxy";
            AmbientCapabilities = ["CAP_NET_ADMIN"];
            CapabilityBoundingSet = ["CAP_NET_ADMIN"];

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
            exec ${lib.getExe pkgs.netbird-proxy}
          '';
        };

        # Reconciled after management is up, so a fresh install converges on the
        # first boot rather than needing a second one.
        systemd.services.netbird-services = {
          description = "Reconcile declared NetBird reverse-proxy services";
          after = ["netbird-management.service" "netbird-proxy.service"];
          wants = ["netbird-management.service"];
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe reconcile;
            LoadCredential = [
              "api-token:${config.sops.secrets."keys/netbird/api-token".path}"
            ];
            # Peers enroll asynchronously, and management may still be starting
            # its HTTP listener, so failing here is expected and recoverable.
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };
      };
    };
  };
}
