# services.alloy — ship this host's journal to loki.
#
# Alloy rather than promtail, which is what this was written against first:
# promtail reached end of life and has been removed from nixpkgs. Alloy is
# grafana's own successor and speaks to loki natively.
#
# Opt-in per host rather than in roles.server, because pioneer must not have
# it: a shipper keeps a position file and buffers to disk, and that host
# already raises its watchdog to 60s because SD-card IO stalls the board hard
# enough to trip it. Its journal is capped at 128 MB instead.
#
# Reads the journal rather than tailing files. /var/log is persisted on every
# impermanent host here, so a restart resumes where it left off instead of
# re-shipping or skipping.
{den, ...}: {
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

      # Alloy's own config language, not YAML. Components are wired by
      # referencing each other's exports, so this reads bottom-up: journal ->
      # relabel -> write.
      config-alloy = pkgs.writeTextDir "config.alloy" ''
        loki.write "default" {
          endpoint {
            url = "http://${cfg.lokiHost}:${toString cfg.lokiPort}/loki/api/v1/push"
          }
        }

        // Kept to a small fixed set on purpose: labels are what loki indexes,
        // and a high-cardinality one (a pid, a request id) is how a loki
        // install becomes unusably slow. `unit` answers the first question
        // anyone asks, which is which service said this.
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
          forward_to    = [loki.write.default.receiver]
          relabel_rules = loki.relabel.journal.rules
          labels        = {
            job  = "systemd-journal",
            host = "${config.networking.hostName}",
          }
          max_age = "12h"
        }
      '';
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

        # The journal is root-readable; alloy runs as its own user, and
        # systemd-journal is the group that grants a reader access to it.
        systemd.services.alloy.serviceConfig.SupplementaryGroups = ["systemd-journal"];
      };
    };
  };
}
