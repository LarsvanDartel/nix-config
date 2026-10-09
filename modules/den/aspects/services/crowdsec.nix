# services.crowdsec — behavioural detection and IP reputation for the edge.
#
# netbird-proxy's access logs never reach disk, so published services rely on
# reputation (the community blocklist — enabled by the capi enroll key, which
# is not optional), not local detection.
{...}: {
  den.aspects.services.crowdsec.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.meta) getExe getExe';
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf str;

    cfg = config.cosmos.services.crowdsec;

    writeYamlFile = (pkgs.formats.yaml {}).generate;

    # Same inputs as the module's own `-c` file, so the same store path.
    configFile = writeYamlFile "crowdsec.yaml" config.services.crowdsec.settings.general;

    etcDefaults = {
      enable = true;
      user = config.services.crowdsec.user;
      group = config.services.crowdsec.group;
      mode = "0770";
    };
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

      sops.secrets."keys/crowdsec/enroll_key".owner = config.services.crowdsec.user;

      systemd.tmpfiles.rules = [
        "d /var/lib/crowdsec 0755 ${config.services.crowdsec.user} ${config.services.crowdsec.group} - -"
        "f /var/lib/crowdsec/online_api_credentials.yaml 0750 ${config.services.crowdsec.user} ${config.services.crowdsec.group} - -"
      ];

      services.crowdsec = {
        enable = true;
        openFirewall = false;
        autoUpdateService = true;

        hub.collections = [
          "crowdsecurity/linux"
          "crowdsecurity/sshd"
          "crowdsecurity/nginx"
        ];

        hub.parsers = ["crowdsecurity/whitelists"];

        localConfig.acquisitions = [
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

        localConfig.profiles = [
          {
            name = "default_ip_remediation";
            filters = ["Alert.Remediation == true && Alert.GetScope() == 'Ip'"];
            decisions = [
              {
                type = "ban";
                duration = "4h";
              }
            ];
            on_success = "break";
          }
          {
            name = "default_range_remediation";
            filters = ["Alert.Remediation == true && Alert.GetScope() == 'Range'"];
            decisions = [
              {
                type = "ban";
                duration = "4h";
              }
            ];
            on_success = "break";
          }
        ];

        settings.general = {
          plugin_config = {
            inherit (config.services.crowdsec) user group;
          };
          api.server = {
            enable = true;
            listen_uri = "127.0.0.1:${toString cfg.lapiPort}";
          };
        };

        # Not under /etc/crowdsec (nix symlink tree); losing these
        # re-registers as a fresh console instance.
        settings.capi.credentialsFile = "/var/lib/crowdsec/online_api_credentials.yaml";
        settings.lapi.credentialsFile = "/var/lib/crowdsec/local_api_credentials.yaml";
        settings.console = {
          tokenFile = config.sops.secrets."keys/crowdsec/enroll_key".path;
          configuration = {
            share_manual_decisions = true;
            share_tainted = true;
            share_custom = true;
            share_context = true;
            console_management = false;
          };
        };
      };

      users.users.${config.services.crowdsec.user}.extraGroups = ["nginx"];

      environment.etc = {
        # The unwrapped cscli (used by the bouncer's registration service)
        # expects config at the default path and dies without it.
        "crowdsec/config.yaml".source = configFile;

        "crowdsec/parsers/s02-enrich/local-whitelist.yaml" =
          etcDefaults
          // {
            source = writeYamlFile "crowdsec-parser-local-whitelist.yaml" {
              name = "local/whitelist";
              description = "Addresses that must never be banned";
              whitelist = {
                reason = "local and mesh traffic";
                ip = cfg.whitelistIps;
                cidr = cfg.whitelistCidrs;
              };
            };
          };

        # Postoverflow: a lookup per alert, not per event.
        "crowdsec/postoverflows/s01-whitelist/fqdn-whitelist.yaml" =
          lib.mkIf (cfg.whitelistFqdns != [])
          (etcDefaults
            // {
              source = writeYamlFile "crowdsec-postoverflow-fqdn-whitelist.yaml" {
                name = "local/fqdn-whitelist";
                description = "Addresses that must never be banned, by name";
                whitelist = {
                  reason = "own hosts";
                  expression =
                    map (n: "evt.Overflow.Alert.Source.IP in LookupHost(${builtins.toJSON n})")
                    cfg.whitelistFqdns;
                };
              };
            });
      };

      services.crowdsec-firewall-bouncer.enable = true;

      # nixpkgs enrols only when the token file is ABSENT (inverted); do it
      # here until fixed upstream. `|| true` so failure never blocks the engine.
      systemd.services.crowdsec.serviceConfig.ExecStartPre = let
        cscli = getExe' config.services.crowdsec.package "cscli";
        inherit (config.services.crowdsec.settings.console) tokenFile;
      in [
        (getExe (pkgs.writeShellScriptBin "crowdsec-enroll" ''
          if [ -e ${lib.escapeShellArg tokenFile} ]; then
            ${cscli} -c=${configFile} console enroll \
              "$(${getExe' pkgs.coreutils "cat"} ${lib.escapeShellArg tokenFile})" \
              --name ${lib.escapeShellArg config.services.crowdsec.name} || true
          fi
        ''))
      ];

      # DynamicUser+StateDirectory hits EBUSY relocating the impermanence
      # bind-mounted /var/lib/crowdsec; the unit never runs, no API key.
      systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.DynamicUser =
        lib.mkForce false;

      # Upstream's script hard-exits if the DB lists the bouncer but the key
      # file (stored elsewhere) is gone — happened on gaia's first impermanence
      # rollback. Drop the stale registration so a fresh key is minted.
      systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.ExecStartPre = [
        "-${pkgs.writeShellScript "crowdsec-drop-stale-bouncer" ''
          key=/var/lib/crowdsec-firewall-bouncer-register/api-key.cred
          cscli=${config.services.crowdsec.package}/bin/cscli
          if [[ ! -f "$key" ]] \
            && "$cscli" bouncers list --output json \
              | ${lib.getExe pkgs.jq} -e -- 'any(.[]; .name == "crowdsec-firewall-bouncer")' >/dev/null; then
            echo "registration without a key; dropping it so one can be reissued"
            "$cscli" bouncers delete crowdsec-firewall-bouncer || true
          fi
        ''}"
      ];

      # nixpkgs sets Requires= but no After=; first boot dies at LoadCredential.
      systemd.services.crowdsec-firewall-bouncer.after = [
        "crowdsec-firewall-bouncer-register.service"
      ];

      # nixpkgs' hub-update ExecStartPost reload is denied by polkit (disabled
      # on these hosts, and not worth enabling), turning the unit red every
      # tick; replaced by OnSuccess= root oneshot below. nixpkgs also lacks
      # ExecReload; SIGHUP (as upstream) avoids dropping bouncer LAPI queries.
      systemd.services.crowdsec.serviceConfig.ExecReload = "${getExe' pkgs.coreutils "kill"} -HUP $MAINPID";

      # `cscli hub update` in ExecStartPre needs DNS and the unit is Restart=no;
      # netbird-proxy fails closed on a dead LAPI, so every published service
      # 403'd for six hours (2026-08-29) after losing a race with unbound.
      # Both guards are needed.
      systemd.services.crowdsec = {
        after = ["nss-lookup.target"];
        wants = ["nss-lookup.target"];
        serviceConfig.Restart = "on-failure";
      };

      systemd.services.crowdsec-update-hub = {
        serviceConfig.ExecStartPost = lib.mkForce [];
        unitConfig.OnSuccess = ["crowdsec-reload.service"];
      };

      systemd.services.crowdsec-reload = {
        description = "Reload crowdsec after a hub index update";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${getExe' pkgs.systemd "systemctl"} reload crowdsec.service";
        };
      };
    };
  };
}
