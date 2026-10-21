# services.crowdsec — behavioural detection and IP reputation for the edge.
#
# netbird-proxy's access logs never reach disk, so published services rely on
# reputation (the community blocklist — enabled by the capi enroll key, which
# is not optional), not local detection.
{...}: {
  den.aspects.services.crowdsec.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf str;

    cfg = config.cosmos.services.crowdsec;
  in {
    options.cosmos.services.crowdsec = {
      lapiPort = mkOption {
        type = lib.types.port;
        default = 8076;
        description = ''
          Loopback port the local API listens on. Both bouncers talk to it, and
          nothing else should: it is deliberately not firewalled open.
        '';
      };

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

      sops.secrets."keys/crowdsec/enroll_key" = {};

      systemd.tmpfiles.rules = [
        "d /var/lib/crowdsec 0755 ${config.services.crowdsec.user} ${config.services.crowdsec.group} - -"
        "f /var/lib/crowdsec/online_api_credentials.yaml 0750 ${config.services.crowdsec.user} ${config.services.crowdsec.group} - -"
      ];

      services.crowdsec = {
        enable = true;
        autoUpdateService = true;

        # nginx's access log. Upstream declares no default, so this must be set.
        extraGroups = ["nginx"];

        hub.collections = [
          "crowdsecurity/linux"
          "crowdsecurity/sshd"
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
            # (/var/lib/crowdsec/data) would orphan the decision DB, the hub and
            # every bouncer registration, netbird-proxy's included.
            config_paths.data_dir = "/var/lib/crowdsec/state";
            db_config.use_wal = true;

            api.server.listen_uri = "127.0.0.1:${toString cfg.lapiPort}";

            # Outside data_dir and /etc/crowdsec (a tmpfiles tree); losing
            # these re-registers as a fresh console instance.
            api.client.credentials_path = "/var/lib/crowdsec/local_api_credentials.yaml";
            api.server.online_client.credentials_path = "/var/lib/crowdsec/online_api_credentials.yaml";
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

      services.crowdsec-firewall-bouncer.enable = true;

      systemd.services.crowdsec-setup = {
        # Upstream's ReadWritePaths covers data_dir only; under DynamicUser's
        # ProtectSystem=strict the credentials above could not be (re)written.
        serviceConfig.ReadWritePaths = ["/var/lib/crowdsec"];

        # `cscli hub update` needs DNS. netbird-proxy fails closed on a dead
        # LAPI, so every published service 403'd for six hours (2026-08-29)
        # after the hub update lost a race with unbound.
        after = ["nss-lookup.target"];
        wants = ["nss-lookup.target"];
      };
    };
  };
}
