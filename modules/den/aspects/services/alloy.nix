# services.alloy — ship this host's journal to loki.
#
# Alloy, not promtail (EOL, gone from nixpkgs). Opt-in per host, not in
# roles.server: pioneer must not run a shipper — SD-card IO already stalls
# its watchdog; its journal is capped at 128 MB instead. Reads the journal,
# and /var/log is persisted on impermanent hosts, so a restart resumes
# rather than re-ships or skips.
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

      # Alloy's own config language, not YAML — components wire via each
      # other's exports, so read bottom-up.
      config-alloy = pkgs.writeTextDir "config.alloy" ''
        loki.write "default" {
          endpoint {
            url = "http://${cfg.lokiHost}:${toString cfg.lokiPort}/loki/api/v1/push"
          }
        }

        // kdeconnectd probes for peers over mDNS on every interface it can
        // see, twice a second. One of those is wt0, NetBird's WireGuard
        // interface, where no peer's AllowedIPs cover the mDNS multicast group
        // 224.0.0.251 — so the kernel refuses the send with ENOKEY and
        // kdeconnect logs "Failed to send mDNS query: Required key not
        // available". Verified by hand: the same send succeeds on the LAN
        // interface and returns ENOKEY on wt0.
        //
        // Nothing is broken. Discovery works over the LAN, which is the only
        // place it could ever work, and a mesh peer is not a thing mDNS is
        // meant to find. It is ~50k identical lines a day that bury everything
        // else this host says.
        //
        // Dropped here because there is nowhere else to drop it: kdeconnect
        // offers no way to restrict which interfaces it probes. If it ever
        // gains one, this goes. The count survives as
        // `loki_process_dropped_lines_total{reason=...}`, so the noise stays
        // measurable even though the lines are gone.
        loki.process "denoise" {
          forward_to = [loki.write.default.receiver]

          stage.drop {
            expression          = "Failed to send mDNS query: Required key not available"
            drop_counter_reason = "kdeconnect_mdns_on_wireguard"
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
          forward_to    = [loki.process.denoise.receiver]
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

        # The journal is root-readable; the systemd-journal group grants
        # alloy's user read access to it.
        systemd.services.alloy.serviceConfig.SupplementaryGroups = ["systemd-journal"];
      };
    };
  };
}
