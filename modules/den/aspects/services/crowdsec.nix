# services.crowdsec — behavioural detection and IP reputation for the edge.
#
# Three aspects:
#   * services.crowdsec.agent  — the log processor, wherever logs are read.
#   * services.crowdsec        — gaia's local API (LAPI): it decides, and its
#     bouncers (the firewall, netbird-proxy) enforce.
#   * services.crowdsec.remote — an agent on another host, reporting to the
#     LAPI. Its alerts become decisions there, so a visitor caught behind the
#     proxy is refused at the edge for every published service.
#
# Neither side names the other: the LAPI publishes its address on the
# `crowdsec-lapi` quirk, remote agents publish themselves on
# `crowdsec-machine`, and the LAPI registers each with a per-machine password
# from hosts/common.
#
# netbird-proxy's own access logs never reach disk, so published services are
# covered by reputation (the community blocklist — enabled by the capi enroll
# key, which is not optional) plus whatever a remote agent reads behind it.
{
  den,
  inputs,
  ...
}: let
  inherit (den.lib.policy) pipe;

  # Not a per-host option: remote agents dial it.
  lapiPort = 8076;

  # Scrape-target ports must be static (see services/prometheus.nix).
  metricsPort = 6060;
  bouncerMetricsPort = 60601;

  commonSecrets = builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";
  machineSecret = name: "keys/crowdsec/machines/${name}";
in {
  den.quirks.crowdsec-lapi.description = "URL of the crowdsec local API, for remote agents";
  den.quirks.crowdsec-machine.description = "Remote crowdsec agents (host names), registered by the local API";

  # collect, not collectAll: LAPI and agents are all x86_64 so far.
  # den reads these argument names (host scope, host-entity filter), so
  # deadnix must not strip them as unused.
  # deadnix: skip
  den.policies.crowdsec-lapi = {host, ...}: [
    (pipe.from "crowdsec-lapi" [
      (pipe.collect (
        # deadnix: skip
        {host, ...}: true
      ))
    ])
  ];

  # deadnix: skip
  den.policies.crowdsec-machine = {host, ...}: [
    (pipe.from "crowdsec-machine" [
      (pipe.collect (
        # deadnix: skip
        {host, ...}: true
      ))
    ])
  ];

  den.aspects.services.crowdsec.agent.includes = [den.aspects.services.netbird.client];

  den.aspects.services.crowdsec.agent.scrape-target = {host, ...}: {
    job = "crowdsec";
    instance = host.name;
    port = metricsPort;
  };

  den.aspects.services.crowdsec.agent.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf str;

    cfg = config.cosmos.services.crowdsec;
  in {
    options.cosmos.services.crowdsec = {
      whitelistCidrs = mkOption {
        type = listOf str;
        default = [
          "127.0.0.1/32"
          "::1/128"
          # The mesh: netbird-proxy's embedded client is a peer, so banning
          # mesh addresses takes out the thing doing the banning.
          "100.64.0.0/10"
          "192.168.0.0/16"
          "10.0.0.0/8"
        ];
        description = "Never ban these, whatever they do.";
      };

      whitelistIps = mkOption {
        type = listOf str;
        default = [];
        description = "Individual addresses to never ban — a home connection, say.";
      };

      whitelistFqdns = mkOption {
        type = listOf str;
        default = ["lvdar.nl"];
        description = ''
          Names resolved at decision time rather than at build time, for
          addresses that move. Costs a lookup per overflow, so keep it short.
        '';
      };
    };

    config = {
      cosmos.system.impermanence.persist.directories = [
        {
          directory = "/var/lib/crowdsec";
          user = config.services.crowdsec.user;
          group = config.services.crowdsec.group;
          mode = "0750";
        }
      ];

      services.crowdsec = {
        enable = true;
        autoUpdateService = true;

        # nginx's access log. Upstream declares no default, so this must be set.
        extraGroups = ["nginx"];

        hub.collections = [
          "crowdsecurity/linux"
          "crowdsecurity/nginx"
        ];

        hub.parsers = ["crowdsecurity/whitelists"];

        settings = {
          acquisitions = [
            {
              source = "file";
              filenames = ["/var/log/nginx/access.log"];
              labels.type = "nginx";
            }
          ];

          parsers.s02Enrich = [
            {
              name = "local/whitelist";
              description = "Addresses that must never be banned";
              whitelist = {
                reason = "local and mesh traffic";
                ip = cfg.whitelistIps;
                cidr = cfg.whitelistCidrs;
              };
            }
          ];

          # Postoverflow: a lookup per alert, not per event.
          postOverflows.s01Whitelist = lib.optional (cfg.whitelistFqdns != []) {
            name = "local/fqdn-whitelist";
            description = "Addresses that must never be banned, by name";
            whitelist = {
              reason = "own hosts";
              expression =
                map (n: "evt.Overflow.Alert.Source.IP in LookupHost(${builtins.toJSON n})")
                cfg.whitelistFqdns;
            };
          };

          config = {
            # The pre-2026-10 module's layout. Upstream's new default
            # (/var/lib/crowdsec/data) would orphan gaia's decision DB, the hub
            # and every bouncer registration, netbird-proxy's included.
            config_paths.data_dir = "/var/lib/crowdsec/state";
            db_config.use_wal = true;

            # 0.0.0.0, not the mesh address (unknown at eval time); the
            # firewall admits it on the mesh interface alone.
            prometheus = {
              enabled = true;
              level = "full";
              listen_addr = "0.0.0.0";
              listen_port = metricsPort;
            };
          };
        };
      };

      cosmos.services.netbird.client.exposedPorts = [metricsPort];

      # `cscli hub update` needs DNS. netbird-proxy fails closed on a dead
      # LAPI, so every published service 403'd for six hours (2026-08-29)
      # after the hub update lost a race with unbound.
      systemd.services.crowdsec-setup = {
        after = ["nss-lookup.target"];
        wants = ["nss-lookup.target"];
      };
    };
  };

  den.aspects.services.crowdsec.remote = {
    includes = with den.aspects.services; [crowdsec.agent den.policies.crowdsec-lapi];

    crowdsec-machine = {host, ...}: host.name;

    nixos = {
      config,
      lib,
      crowdsec-lapi,
      ...
    }: let
      secret = machineSecret config.networking.hostName;
    in {
      assertions = [
        {
          assertion = lib.length crowdsec-lapi == 1;
          message = "services.crowdsec.remote needs exactly one host with services.crowdsec; found ${toString (lib.length crowdsec-lapi)}.";
        }
      ];

      sops.secrets.${secret}.sopsFile = commonSecrets;

      sops.templates."crowdsec-lapi-credentials.yaml" = {
        content = ''
          url: ${lib.head (crowdsec-lapi ++ [""])}
          login: ${config.services.crowdsec.name}
          password: ${config.sops.placeholder.${secret}}
        '';
        owner = config.services.crowdsec.user;
        restartUnits = ["crowdsec.service"];
      };

      services.crowdsec.settings.config.api = {
        server.enable = false;
        client.credentials_path = config.sops.templates."crowdsec-lapi-credentials.yaml".path;
      };
    };
  };

  den.aspects.services.crowdsec = {
    includes = with den.aspects.services; [crowdsec.agent netbird.client den.policies.crowdsec-machine];

    crowdsec-lapi = {host, ...}: "http://${host.meshAddress}:${toString lapiPort}";

    scrape-target = {host, ...}: {
      job = "crowdsec-firewall-bouncer";
      instance = host.name;
      port = bouncerMetricsPort;
    };

    nixos = {
      config,
      lib,
      crowdsec-machine,
      ...
    }: let
      inherit (lib.modules) mkIf;
      inherit (lib.strings) concatMapStrings escapeShellArg;

      remote = crowdsec-machine != [];
    in {
      options.cosmos.services.crowdsec.lapiPort = lib.mkOption {
        type = lib.types.port;
        default = lapiPort;
        readOnly = true;
        description = ''
          Port the local API listens on, for this host's bouncers (the
          firewall, netbird-proxy). Remote agents get the URL from the
          `crowdsec-lapi` quirk, which is why it cannot vary per host.
        '';
      };

      config = {
        sops.secrets =
          {"keys/crowdsec/enroll_key" = {};}
          // lib.genAttrs (map machineSecret crowdsec-machine) (_: {
            sopsFile = commonSecrets;
            restartUnits = ["crowdsec-machines.service"];
          });

        systemd.tmpfiles.rules = [
          "d /var/lib/crowdsec 0755 ${config.services.crowdsec.user} ${config.services.crowdsec.group} - -"
          "f /var/lib/crowdsec/online_api_credentials.yaml 0750 ${config.services.crowdsec.user} ${config.services.crowdsec.group} - -"
        ];

        # Mesh only: the bouncer's metrics, and the LAPI when remote agents
        # dial it. The bouncers themselves query the LAPI over loopback.
        cosmos.services.netbird.client.exposedPorts =
          [bouncerMetricsPort]
          ++ lib.optional remote lapiPort;

        services.crowdsec = {
          hub.collections = ["crowdsecurity/sshd"];

          settings = {
            acquisitions = [
              {
                source = "journalctl";
                journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
                labels.type = "syslog";
              }
              {
                source = "journalctl";
                journalctl_filter = ["_TRANSPORT=kernel"];
                labels.type = "syslog";
              }
            ];

            config.api = {
              # 0.0.0.0, not the mesh address (unknown at eval time); the
              # firewall admits it on the mesh interface alone.
              server.listen_uri = "${
                if remote
                then "0.0.0.0"
                else "127.0.0.1"
              }:${toString lapiPort}";

              # Outside data_dir and /etc/crowdsec (a tmpfiles tree); losing
              # these re-registers as a fresh console instance.
              client.credentials_path = "/var/lib/crowdsec/local_api_credentials.yaml";
              server.online_client.credentials_path = "/var/lib/crowdsec/online_api_credentials.yaml";
            };

            console = {
              enrollKeyFile = config.sops.secrets."keys/crowdsec/enroll_key".path;
              configuration = {
                share_manual_decisions = true;
                share_tainted = true;
                share_custom = true;
                share_context = true;
                console_management = false;
              };
            };
          };
        };

        services.crowdsec-firewall-bouncer = {
          enable = true;
          settings.prometheus = {
            enabled = true;
            listen_addr = "0.0.0.0";
            listen_port = bouncerMetricsPort;
          };
        };

        # Upstream's ReadWritePaths covers data_dir only; under DynamicUser's
        # ProtectSystem=strict the credentials above could not be (re)written.
        systemd.services.crowdsec-setup.serviceConfig.ReadWritePaths = ["/var/lib/crowdsec"];

        # --force upserts, so a rotated password takes effect. `-f /dev/null`
        # is load-bearing: without it, --force writes the new machine's
        # credentials over this host's own local_api_credentials.yaml.
        systemd.services.crowdsec-machines = mkIf remote {
          description = "Register remote crowdsec agents with the local API";
          after = ["crowdsec.service"];
          requires = ["crowdsec.service"];
          wantedBy = ["crowdsec.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [config.services.crowdsec.package];
          script =
            concatMapStrings (m: ''
              cscli machines add ${escapeShellArg m} --force -f /dev/null \
                --password "$(cat ${config.sops.secrets.${machineSecret m}.path})"
            '')
            crowdsec-machine;
        };
      };
    };
  };
}
