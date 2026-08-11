# services.prometheus — the metrics store, its alert rules, and the bridge
# that turns a firing alert into the same phone notification a failed unit
# already produces.
#
# On endeavour because it is the only host with room: gaia has 3.7 GiB of RAM
# and 21 GB free, pioneer has 866 MiB and an SD card.
#
# Data stays on the system SSD, not /tank, despite /tank being where the
# terabytes are. Three hosts at a 30s interval is roughly 5000 series, which
# for 90 days works out around 3 GB — against 146 GB free. Moving it to the
# pool would mean fighting the nixpkgs module, which hardcodes
# --storage.tsdb.path under its StateDirectory, to buy headroom that is not
# needed. Loki is the one that will want the array.
#
# Scrapes the three servers over the mesh by name. voyager is deliberately
# absent: see services/node-exporter.nix.
#
# Note the asymmetry with core.notify-failure, which is intentional. That runs
# on each host and reports a unit *transition* to failed, and keeps working
# when this host is down. This reports *states* and thresholds — a disk filling
# up, a pool degrading, a host that stopped answering — which no per-host hook
# can see. They overlap on "unit failed" and that is fine; the duplicate is
# cheaper than the gap would be.
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
      inherit (lib.types) port str attrsOf;

      cfg = config.cosmos.services.prometheus;
      nodePort = config.cosmos.services.node-exporter.port;
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
          type = attrsOf str;
          default = {};
          example = {gaia = "100.68.38.155";};
          description = ''
            Peer name -> address to scrape. The name becomes the `instance`
            label; the address is what is dialled.

            Addresses rather than `<peer>.<dnsDomain>` names, because mesh
            names do not resolve on this host. unbound holds :53 here, so the
            NetBird client could not install itself as the system resolver and
            fell back to an ephemeral port — leaving unbound to answer
            `*.lvdar.nl` from public DNS. A scrape of `gaia.nb.lvdar.nl` there
            resolves to gaia's *public* address and quietly leaves the mesh.

            So these are literals, for the same reason
            `cosmos.services.netbird.oidc.idp.upstream` in hosts/gaia.nix is a
            literal: NetBird assigns the address at enrollment and nothing here
            can read another host's config. They only change if a peer is
            re-enrolled. Fixing the resolver would remove the need for this and
            is the better long-term answer.

            Not voyager: a laptop that sleeps would sit permanently "down".
          '';
        };
      };

      config = {
        # The bridge authenticates to ntfy as the same account every host
        # publishes as. A template rather than a plain secret because
        # alertmanager-ntfy wants credentials inside its YAML.
        sops = {
          secrets."keys/ntfy/password".sopsFile =
            builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

          templates."alertmanager-ntfy-auth.yml".content = ''
            ntfy:
              user: ${config.cosmos.system.notifyFailure.user}
              password: ${config.sops.placeholder."keys/ntfy/password"}
          '';
        };

        # Static prometheus user, no DynamicUser, so this is the ordinary
        # persist shape and not the /var/lib/private EBUSY case that ntfy hit.
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
              # One static_config per peer, so `instance` is the peer's name
              # rather than an IP nobody can read off a graph.
              static_configs =
                lib.mapAttrsToList (name: addr: {
                  targets = ["${addr}:${toString nodePort}"];
                  labels.instance = name;
                })
                cfg.targets;
            }
            {
              # Already exported, never read until now. Gives peer counts,
              # login expiry and gRPC health for the control plane the whole
              # mesh depends on.
              job_name = "netbird";
              static_configs = [
                {
                  targets = ["${cfg.targets.gaia or "127.0.0.1"}:9090"];
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
                      # pioneer was at 89% before the journald cap, so this is
                      # not hypothetical.
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
                      # The gap the plan called out: a raidz1 losing a disk
                      # currently produces one journal line and nothing else.
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
                # Grouped so a host going down produces one notification and
                # not one per alerting rule that trips as a consequence.
                group_by = ["alertname" "instance"];
                group_wait = "30s";
                group_interval = "5m";
                # Deliberately long. A phone notification repeated every four
                # hours is a reminder; every five minutes is something you mute,
                # and a muted channel is worse than no channel.
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

        # Alertmanager speaks its own webhook schema; ntfy speaks its own. This
        # translates, and is packaged for exactly this job.
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
          # Credentials arrive as a systemd credential, so the password never
          # reaches the store or the unit file.
          extraConfigFiles = [config.sops.templates."alertmanager-ntfy-auth.yml".path];
        };

        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
