# services.prometheus — the metrics store, its alert rules, and the bridge
#
# On endeavour, the only host with room. Data stays on the SSD: the nixpkgs
# module hardcodes --storage.tsdb.path under its StateDirectory.
#
# Complements core.notify-failure: that reports unit transitions and survives
# this host dying; this reports states and thresholds no per-host hook sees.
{
  den,
  inputs,
  ...
}: {
  den.aspects.services.prometheus = {
    includes = with den.aspects.services; [netbird.client node-exporter];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str listOf;

      cfg = config.cosmos.services.prometheus;
      nodePort = config.cosmos.services.node-exporter.port;
      dnsDomain = config.cosmos.services.netbird.dnsDomain;
    in {
      options.cosmos.services.prometheus = {
        port = mkOption {
          type = port;
          default = 9090;
          description = ''
            Free on this host. Note it is *not* free on gaia, where netbird
            management serves its own metrics on 9090 — which is a scrape
            target below, not a conflict.
          '';
        };

        alertmanagerPort = mkOption {
          type = port;
          default = 9093;
        };

        bridgePort = mkOption {
          type = port;
          default = 9099;
          description = "Loopback-only webhook receiver that forwards to ntfy.";
        };

        retention = mkOption {
          type = str;
          default = "90d";
          description = "Passed through as retentionTime.";
        };

        targets = mkOption {
          type = listOf str;
          default = ["endeavour" "gaia" "pioneer"];
          description = ''
            Peer names, dialled as `<name>.${dnsDomain}` over the mesh.

            Names work here only because services/unbound.nix forwards the mesh
            domain to the NetBird agent's resolver. Before that, unbound
            answered *.lvdar.nl from public DNS and every one of these
            resolved to the edge's public address — the scrapes left the mesh
            and timed out. If these ever start timing out again, check mesh DNS
            on this host before suspecting the exporters.

            Not voyager: a laptop that sleeps would sit permanently "down".
          '';
        };
      };

      config = {
        # A template: alertmanager-ntfy wants credentials inside its YAML.
        sops = {
          secrets."keys/ntfy/password".sopsFile =
            builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

          templates."alertmanager-ntfy-auth.yml".content = ''
            ntfy:
              user: ${config.cosmos.system.notifyFailure.user}
              password: ${config.sops.placeholder."keys/ntfy/password"}
          '';
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/${config.services.prometheus.stateDir}";
            user = "prometheus";
            group = "prometheus";
            mode = "0700";
          }
        ];

        services.prometheus = {
          enable = true;
          inherit (cfg) port;
          retentionTime = cfg.retention;

          globalConfig = {
            scrape_interval = "30s";
            evaluation_interval = "30s";
          };

          scrapeConfigs = [
            {
              job_name = "node";
              # One static_config per peer so `instance` is the bare peer name.
              static_configs =
                map (h: {
                  targets = ["${h}.${dnsDomain}:${toString nodePort}"];
                  labels.instance = h;
                })
                cfg.targets;
            }
            {
              job_name = "netbird";
              static_configs = [
                {
                  targets = ["gaia.${dnsDomain}:9090"];
                  labels.instance = "gaia";
                }
              ];
            }
            {
              job_name = "prometheus";
              static_configs = [{targets = ["127.0.0.1:${toString cfg.port}"];}];
            }
          ];

          alertmanagers = [
            {
              static_configs = [
                {targets = ["127.0.0.1:${toString cfg.alertmanagerPort}"];}
              ];
            }
          ];

          rules = [
            (builtins.toJSON {
              groups = [
                {
                  name = "fleet";
                  rules = [
                    {
                      alert = "HostDown";
                      expr = "up{job=\"node\"} == 0";
                      for = "5m";
                      labels.severity = "critical";
                      annotations = {
                        summary = "{{ $labels.instance }} is not answering";
                        description = "No successful scrape for 5 minutes.";
                      };
                    }
                    {
                      alert = "UnitFailed";
                      expr = "node_systemd_unit_state{state=\"failed\"} == 1";
                      for = "5m";
                      labels.severity = "warning";
                      annotations = {
                        summary = "{{ $labels.instance }}: {{ $labels.name }} failed";
                        description = "The unit has been in failed state for 5 minutes.";
                      };
                    }
                    {
                      alert = "DiskFilling";
                      expr = ''
                        100 - (node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay"}
                          / node_filesystem_size_bytes * 100) > 85
                      '';
                      for = "30m";
                      labels.severity = "warning";
                      annotations = {
                        summary = "{{ $labels.instance }}: {{ $labels.mountpoint }} over 85% full";
                        description = "{{ $value | printf \"%.0f\" }}% used.";
                      };
                    }
                    {
                      alert = "ZfsPoolUnhealthy";
                      expr = "node_zfs_zpool_state{state!=\"online\"} > 0";
                      for = "5m";
                      labels.severity = "critical";
                      annotations = {
                        summary = "{{ $labels.instance }}: pool {{ $labels.zpool }} is {{ $labels.state }}";
                        description = "Check zpool status.";
                      };
                    }
                    {
                      # Catches a backup that stops being attempted, which
                      # core.notify-failure cannot see.
                      alert = "ResticStale";
                      expr = ''
                        time() - node_systemd_timer_last_trigger_seconds{name="restic-backups-stardust.timer"} > 172800
                      '';
                      for = "1h";
                      labels.severity = "critical";
                      annotations = {
                        summary = "{{ $labels.instance }}: no backup in over 48h";
                        description = "The stardust timer has not fired since {{ $value | humanizeTimestamp }}.";
                      };
                    }
                    {
                      alert = "MemoryPressure";
                      expr = ''
                        node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 10
                      '';
                      for = "15m";
                      labels.severity = "warning";
                      annotations = {
                        summary = "{{ $labels.instance }} is low on memory";
                        description = "{{ $value | printf \"%.0f\" }}% available.";
                      };
                    }
                  ];
                }
              ];
            })
          ];

          alertmanager = {
            enable = true;
            port = cfg.alertmanagerPort;
            configuration = {
              route = {
                receiver = "ntfy";
                group_by = ["alertname" "instance"];
                group_wait = "30s";
                group_interval = "5m";
                # Deliberately long: a channel that nags gets muted.
                repeat_interval = "12h";
              };
              receivers = [
                {
                  name = "ntfy";
                  webhook_configs = [
                    {url = "http://127.0.0.1:${toString cfg.bridgePort}/";}
                  ];
                }
              ];
            };
          };
        };

        services.prometheus.alertmanager-ntfy = {
          enable = true;
          settings = {
            http.addr = "127.0.0.1:${toString cfg.bridgePort}";
            ntfy = {
              baseurl = config.cosmos.system.notifyFailure.url;
              notification = {
                inherit (config.cosmos.system.notifyFailure) topic;
                priority = ''status == "firing" ? "high" : "default"'';
              };
            };
          };
          extraConfigFiles = [config.sops.templates."alertmanager-ntfy-auth.yml".path];
        };

        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
