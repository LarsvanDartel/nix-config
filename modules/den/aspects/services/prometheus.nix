# services.prometheus — the fleet's metrics store on endeavour, its alert rules and the alertmanager-ntfy bridge.
{
  den,
  inputs,
  lib,
  ...
}: let
  inherit (den.lib.policy) pipe;

  # Servers a bare `deploy` covers (meta/deploy.nix); the rest are deployed
  # on their own schedule and would otherwise fire DeployBehind after every push.
  tracked = lib.attrNames (lib.filterAttrs (_: h: h.server && h.deployByDefault) (lib.mergeAttrsList (lib.attrValues den.hosts)));
  behind = ''nixos_configuration_info{instance=~"${lib.concatStringsSep "|" tracked}"} unless on(revision) nix_config_main_info'';
in {
  den.quirks.scrape-target.description = "Prometheus scrape targets ({job, instance, port}), collected by services.prometheus";

  # collectAll, not collect: pioneer is aarch64. Payloads must be static or `{host, ...}:`;
  # a `{config, ...}:` payload makes this host evaluate every other host.
  # deadnix: skip
  den.policies.scrape-target = {host, ...}: [
    (pipe.from "scrape-target" [
      (pipe.collectAll (
        # deadnix: skip
        {host, ...}: true
      ))
    ])
  ];

  den.aspects.services.prometheus = {
    includes = with den.aspects.services; [netbird.client node-exporter den.policies.scrape-target];

    nixos = {
      config,
      lib,
      scrape-target,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;
      inherit (lib.lists) groupBy sortOn;
      inherit (lib.attrsets) mapAttrsToList;

      cfg = config.cosmos.services.prometheus;
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

          # One static_config per instance so `instance` is the bare peer name. Names resolve in the
          # mesh only through services/unbound.nix's forward; if scrapes time out, check mesh DNS first.
          scrapeConfigs =
            mapAttrsToList (job: entries: {
              job_name = job;
              static_configs =
                map (e: {
                  targets = ["${e.instance}.${dnsDomain}:${toString e.port}"];
                  labels.instance = e.instance;
                })
                (sortOn (e: e.instance) entries);
            })
            (groupBy (e: e.job) scrape-target)
            ++ [
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
                    {
                      # One fleet-wide alert: a push leaves every server behind at once. Silent while main's head
                      # is unknown; HostDown covers endeavour's exporter.
                      alert = "DeployBehind";
                      expr = ''
                        count(${behind})
                          and on() count(nix_config_main_info)
                      '';
                      for = "1h";
                      labels.severity = "warning";
                      annotations = {
                        summary = "{{ $value }} host(s) not running main";
                        description = ''
                          {{ range query `${behind}` }}{{ .Labels.instance }} runs {{ reReplaceAll "^([0-9a-f]{7})[0-9a-f]*" "$1" .Labels.revision }}
                          {{ end }}main is {{ with query "nix_config_main_info" }}{{ reReplaceAll "^([0-9a-f]{7})[0-9a-f]*" "$1" (index . 0).Labels.revision }}{{ end }}. Pull and run `deploy` on voyager; a host ahead of main has an unpushed or dirty deploy.
                        '';
                      };
                    }
                    {
                      alert = "NixpkgsStale";
                      expr = "count(time() - nixos_nixpkgs_last_modified_seconds > ${toString (7 * 86400)})";
                      for = "30m";
                      labels.severity = "warning";
                      annotations = {
                        summary = "{{ $value }} host(s) on nixpkgs older than a week";
                        description = ''
                          {{ range query "time() - nixos_nixpkgs_last_modified_seconds > ${toString (7 * 86400)}" }}{{ .Labels.instance }}: {{ humanizeDuration .Value }}
                          {{ end }}On voyager: `nix flake update`, commit, `deploy`, push.
                        '';
                      };
                    }
                  ];
                }
                {
                  name = "crowdsec";
                  rules = [
                    {
                      alert = "CrowdsecDown";
                      expr = "up{job=\"crowdsec\"} == 0";
                      for = "5m";
                      labels.severity = "critical";
                      annotations = {
                        summary = "crowdsec on {{ $labels.instance }} is not answering";
                        description = "On the LAPI host netbird-proxy fails closed: every published service gets 403 (2026-08-29).";
                      };
                    }
                    {
                      # Covers a LAPI that runs but refuses a bouncer (a wiped
                      # database invalidating netbird-proxy's key, say).
                      alert = "CrowdsecBouncerSilent";
                      expr = "sum by (instance, bouncer) (rate(cs_lapi_bouncer_requests_total[10m])) == 0";
                      for = "5m";
                      labels.severity = "critical";
                      annotations = {
                        summary = "{{ $labels.bouncer }} stopped polling the crowdsec LAPI";
                        description = "No decision pulls for 15 minutes; netbird-proxy fails closed, the firewall bouncer stops enforcing.";
                      };
                    }
                    {
                      alert = "CrowdsecAgentSilent";
                      expr = "time() - cs_machines_last_heartbeat_timestamp > 300";
                      for = "5m";
                      labels.severity = "warning";
                      annotations = {
                        summary = "crowdsec agent {{ $labels.machine }} lost the LAPI";
                        description = "Last heartbeat {{ $value | humanizeDuration }} ago. A decommissioned agent keeps its registration: `cscli machines delete` it on the LAPI host.";
                      };
                    }
                    {
                      # File sources only: sshd and kernel journals legitimately
                      # go quiet for hours.
                      alert = "CrowdsecNotReading";
                      expr = "sum by (instance, source) (rate(cs_filesource_hits_total[2h])) == 0";
                      for = "1h";
                      labels.severity = "warning";
                      annotations = {
                        summary = "crowdsec on {{ $labels.instance }} stopped reading {{ $labels.source }}";
                        description = "No lines for 3 hours: rotated away, wrong path, or lost permission.";
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
