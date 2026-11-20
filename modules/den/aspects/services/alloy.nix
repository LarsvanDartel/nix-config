# services.alloy — ships this host's journal (and nginx logs) to loki.
{den, ...}: {
  # Opt-in per host, not in roles.server: pioneer's SD-card IO already stalls its watchdog.
  den.aspects.services.alloy = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.alloy;
      nginx = config.services.nginx.enable;

      config-alloy = pkgs.writeTextDir "config.alloy" (''
          loki.write "default" {
            endpoint {
              url = "http://${cfg.lokiHost}:${toString cfg.lokiPort}/loki/api/v1/push"
            }
          }

          // kdeconnect's mDNS probes fail on wt0 with ENOKEY (no AllowedIPs cover 224.0.0.251), ~50k lines a day,
          // and it cannot restrict interfaces. Dropped lines stay counted in loki_process_dropped_lines_total.
          loki.process "denoise" {
            forward_to = [loki.write.default.receiver]

            stage.drop {
              expression          = "Failed to send mDNS query: Required key not available"
              drop_counter_reason = "kdeconnect_mdns_on_wireguard"
            }
          }

          // Keep labels few and low-cardinality: loki indexes them, and a pid or request id makes it unusably slow.
          loki.relabel "journal" {
            forward_to = []

            rule {
              source_labels = ["__journal__systemd_unit"]
              target_label  = "unit"
            }

            rule {
              source_labels = ["__journal_priority_keyword"]
              target_label  = "level"
            }
          }

          loki.source.journal "read" {
            forward_to    = [loki.process.denoise.receiver]
            relabel_rules = loki.relabel.journal.rules
            labels        = {
              job  = "systemd-journal",
              host = "${config.networking.hostName}",
            }
            max_age = "12h"
          }
        ''
        + lib.optionalString nginx ''

          local.file_match "nginx" {
            path_targets = [
              {"__path__" = "/var/log/nginx/access.log", "log" = "access"},
              {"__path__" = "/var/log/nginx/error.log", "log" = "error"},
            ]
          }

          // From the end: positions do not survive an impermanent reboot, and
          // re-reading a whole rotated log would replay it into loki.
          loki.source.file "nginx" {
            targets       = local.file_match.nginx.targets
            forward_to    = [loki.process.nginx.receiver]
            tail_from_end = true
          }

          // The *arr clients put their API keys in query strings; keep them out of loki.
          loki.process "nginx" {
            forward_to = [loki.write.default.receiver]

            stage.replace {
              expression = "(?i)api_?key=([^&\\s\"]+)"
              replace    = "<redacted>"
            }

            stage.static_labels {
              values = {
                job  = "nginx",
                host = "${config.networking.hostName}",
              }
            }
          }
        '');
    in {
      options.cosmos.services.alloy = {
        lokiHost = mkOption {
          type = str;
          default = "endeavour.${config.cosmos.services.netbird.dnsDomain}";
          description = ''
            Where loki is, by mesh name. Names resolve here because
            services/unbound.nix forwards the mesh domain to the NetBird
            agent's resolver — before that they answered with the edge's
            public address, and this would have shipped logs to the internet.
          '';
        };

        lokiPort = mkOption {
          type = port;
          default = 3100;
        };
      };

      config = {
        services.alloy = {
          enable = true;
          configPath = config-alloy;
        };

        systemd.services.alloy.serviceConfig.SupplementaryGroups =
          ["systemd-journal"]
          ++ lib.optional nginx "nginx";
      };
    };
  };
}
