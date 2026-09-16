# services.loki — one place to grep four hosts' journals from.
#
# On endeavour; data on /tank because logs grow without bound and the 250 GB
# system SSD already carries every service's state. Deliberately NOT in
# cosmos.system.impermanence.persist: /tank is a ZFS pool outside the persist
# layer, and an entry there bind-mounts /persist over it — putting the logs
# back on the SSD (hosts/endeavour.nix documents this twice). Shipped to by
# endeavour, gaia, voyager; not pioneer (SD-card watchdog, see alloy.nix).
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
          example = "/srv/monitoring/loki";
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
              # Quiet: loki logs every push at info, and this host ships its own
              # journal to it — it would log about logging.
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
              # Journald timestamps lag after an offline host flushes on
              # reconnect; rejecting them would drop exactly the outage logs.
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
