# services.loki — one place to grep four hosts' journals from.
#
# On endeavour with the rest of the stack, and unlike prometheus its data does
# go on /tank: logs are the part that grows without a bound anyone chose, and
# the 250 GB system SSD already carries every service's state. The path is
# deliberately NOT added to cosmos.system.impermanence.persist — /tank is a ZFS
# pool outside the persist layer, and an entry there would bind-mount /persist
# over the top and put the logs back on the SSD. hosts/endeavour.nix documents
# that trap twice.
#
# Shipped to by endeavour, gaia and voyager. Explicitly not pioneer: a shipper
# keeps a position file and buffers, and hosts/pioneer.nix already raises the
# watchdog to 60s because SD-card IO stalls the board hard enough to trip it.
# Its journal is capped at 128 MB instead, which is the cheaper answer for a
# host running thirteen services.
{den, ...}: {
  den.aspects.services.loki = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str path;

      cfg = config.cosmos.services.loki;
    in {
      options.cosmos.services.loki = {
        port = mkOption {
          type = port;
          default = 3100;
          description = "Free on this host; 3003 and 3030 are not.";
        };

        dataDir = mkOption {
          type = path;
          default = "/tank/monitoring/loki";
          description = "On the array. See the header for why it is not persisted.";
        };

        retention = mkOption {
          type = str;
          default = "720h";
          description = ''
            30 days, matching the journald cap in core/journald.nix — there is
            no point keeping a central copy for longer than the window anyone
            asks questions about, and every extra day is array space.
          '';
        };
      };

      config = {
        systemd.tmpfiles.rules = [
          "d /tank/monitoring 0750 loki loki - -"
          "d ${cfg.dataDir} 0750 loki loki - -"
          "d ${cfg.dataDir}/chunks 0750 loki loki - -"
          "d ${cfg.dataDir}/rules 0750 loki loki - -"
          "d ${cfg.dataDir}/compactor 0750 loki loki - -"
        ];

        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        services.loki = {
          enable = true;
          configuration = {
            auth_enabled = false;

            server = {
              http_listen_address = "0.0.0.0";
              http_listen_port = cfg.port;
              # Quiet: loki logs every push at info, and this host ships its
              # own journal to it — which would then log about logging.
              log_level = "warn";
            };

            common = {
              path_prefix = cfg.dataDir;
              storage.filesystem = {
                chunks_directory = "${cfg.dataDir}/chunks";
                rules_directory = "${cfg.dataDir}/rules";
              };
              replication_factor = 1;
              ring.kvstore.store = "inmemory";
            };

            schema_config.configs = [
              {
                from = "2024-01-01";
                store = "tsdb";
                object_store = "filesystem";
                schema = "v13";
                index = {
                  prefix = "index_";
                  period = "24h";
                };
              }
            ];

            limits_config = {
              retention_period = cfg.retention;
              # Journald timestamps can lag when a host has been offline and
              # flushes on reconnect; rejecting those would silently lose
              # exactly the logs from the outage being investigated.
              reject_old_samples = false;
            };

            compactor = {
              working_directory = "${cfg.dataDir}/compactor";
              retention_enabled = true;
              delete_request_store = "filesystem";
            };

            analytics.reporting_enabled = false;
          };
        };
      };
    };
  };
}
