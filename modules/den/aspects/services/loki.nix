# services.loki — one place to grep four hosts' journals from.
#
# Data on /tank, deliberately NOT in cosmos.system.impermanence.persist: an
# entry there bind-mounts /persist over it, putting the logs back on the SSD.
{den, ...}: {
  den.aspects.services.loki = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str path;

      cfg = config.cosmos.services.loki;
      proxy = config.cosmos.services.netbird.client.proxyAddress;
      alertmanager = config.services.prometheus.alertmanager;

      # A store path, so a changed rule restarts loki with it. "fake" is the
      # tenant loki assumes with auth_enabled = false.
      rulesDir = pkgs.writeTextDir "fake/rules.yaml" (builtins.toJSON {
        groups = lib.optional (proxy != null) {
          name = "logs";
          rules = [
            {
              # proxyAddress is hand-synced (hosts/endeavour.nix). When
              # netbird-proxy moves, nginx stops restoring visitors and the
              # mesh whitelist hides them all from crowdsec (until 2026-10-21).
              # Gatus keeps a steady trickle through the proxy, so drift shows.
              alert = "ProxyAddressDrift";
              expr = ''sum(count_over_time({job="nginx", log="access", host="${config.networking.hostName}"} |~ `^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.` !~ `^${lib.escapeRegex proxy} ` [15m])) > 5'';
              for = "15m";
              labels.severity = "warning";
              annotations = {
                summary = "netbird-proxy is no longer at ${proxy}";
                description = "{{ $value }} proxied requests in 15 minutes came from another mesh address: update cosmos.services.netbird.client.proxyAddress.";
              };
            }
          ];
        };
      });
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
              # loki logs every push at info, and this host ships to itself.
              log_level = "warn";
            };

            common = {
              path_prefix = cfg.dataDir;
              storage.filesystem.chunks_directory = "${cfg.dataDir}/chunks";
              replication_factor = 1;
              ring.kvstore.store = "inmemory";
            };

            ruler = {
              storage = {
                type = "local";
                local.directory = "${rulesDir}";
              };
              alertmanager_url = lib.mkIf alertmanager.enable "http://127.0.0.1:${toString alertmanager.port}";
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
