# services.crowdsec — behavioural detection and IP reputation for the edge.
#
# Detection reads nginx's access log (control plane, IdP) and the journal
# (sshd, kernel). netbird-proxy's access logs go to management over gRPC,
# never to disk, so the published services rely on reputation, not
# behaviour. Remediation is two bouncers: the firewall bouncer drops bans in
# nftables before TLS — the half that sheds crawler load — and netbird-proxy
# queries the same LAPI per request, so a blocked visitor gets an answer,
# not a timeout, and decisions apply even to traffic the firewall lets
# through.
#
# Most of the value is the community blocklist, not local detection: the
# traffic is opportunistic scanning from addresses burned elsewhere. The
# capi enroll key is what turns that on; it is not optional garnish.
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

    # The same file the module generates for its own `-c` flag — identical
    # inputs, so identical store path: a second reference, not a second copy.
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
          # The mesh: every peer reaches the edge through it, and the reverse
          # proxy's own embedded client is a peer — banning one takes out the
          # thing doing the banning.
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
        # The LAPI is loopback-only and both bouncers are local.
        openFirewall = false;
        autoUpdateService = true;

        hub.collections = [
          "crowdsecurity/linux"
          "crowdsecurity/sshd"
          # Brings in base-http-scenarios and http-cve: scanner probes, path
          # traversal, CVE payloads. The collection that reads what nginx
          # writes.
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

        # Under the state directory, not /etc/crowdsec: written at runtime and
        # must survive a reboot (losing them re-registers as a fresh console
        # instance), while /etc/crowdsec is an nix-generated symlink tree a
        # bind-mount would hide config.yaml under.
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

      # nginx's log directory is mode 0750, owned by nginx.
      users.users.${config.services.crowdsec.user}.extraGroups = ["nginx"];

      environment.etc = {
        # The crowdsec module keeps config.yaml in the store and ships a `cscli`
        # wrapper that passes `-c` to it, so nothing ever lands at the default
        # path. Anything calling the unwrapped binary then dies with "open
        # /etc/crowdsec/config.yaml: no such file or directory" — which is what
        # the firewall bouncer's own registration service does, taking the
        # bouncer down with it, and what any interactive `cscli` would do too.
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

        # Resolved late, in a postoverflow, because a name lookup per event is
        # wasteful where a lookup per alert is not.
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

      # Drops decisions into nftables, so a banned address never completes a
      # TLS handshake — the half that sheds load, not just answers politely.
      services.crowdsec-firewall-bouncer.enable = true;

      # nixpkgs enrols only when the token file is ABSENT — inverted, so with
      # a real token nothing is ever sent. Do it here until fixed upstream;
      # `console enroll` is idempotent, and failure must not keep the engine
      # down, hence the `|| true`.
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

      # nixpkgs gives the registration service DynamicUser and a
      # StateDirectory that includes crowdsec's own: systemd insists on
      # relocating /var/lib/crowdsec under /var/lib/private, which cannot
      # work once impermanence has bind-mounted it — EBUSY, the unit never
      # runs, no API key is written, and the bouncer dies at LoadCredential.
      # It runs as the crowdsec user regardless, so static allocation costs
      # nothing.
      systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.DynamicUser =
        lib.mkForce false;

      # Upstream's registration script hard-exits with "Bouncer registered
      # but API key is not present" when the database still lists the bouncer
      # while the key file has gone — they live in different places (database
      # under /var/lib/crowdsec/state, key under
      # /var/lib/crowdsec-firewall-bouncer-register), so losing one but not
      # the other wedges the unit; no branch in the script recovers. Exactly
      # what the first impermanence rollback did on gaia (2026-08-12):
      # database survived on /persist, key did not, bouncer down through
      # every restart. Dropping the stale registration lets it mint a fresh
      # key.
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

      # nixpkgs gives the bouncer Requires= on the registration service but
      # no After= — no ordering at all. On the very first boot the bouncer
      # reaches LoadCredential before the API key exists and dies at step
      # CREDENTIALS; it works ever after, which is what makes the first
      # deploy so confusing.
      systemd.services.crowdsec-firewall-bouncer.after = [
        "crowdsec-firewall-bouncer-register.service"
      ];

      # nixpkgs ends the hub-update timer with
      # `ExecStartPost=systemctl reload crowdsec.service` run under an
      # unprivileged DynamicUser — polkit refuses it and the unit goes red on
      # every tick: whole host degraded, OnFailure ntfy, a standing false
      # alarm. A polkit rule is not the fix — security.polkit.enable is false
      # on these headless hosts, so extraConfig renders into a configuration
      # nothing reads (/etc/polkit-1/rules.d does not exist; verified on the
      # host). Enabling polkitd on a public VPS to authorise one reload is
      # not worth the attack surface.
      #
      # Instead, OnSuccess= below fires a root-owned oneshot when the update
      # exits cleanly. Underneath the permission denial sat a second bug:
      # nixpkgs never gives crowdsec.service an ExecReload, so the reload
      # could not have worked even as root. Upstream's own unit reloads on
      # SIGHUP, which the engine handles by re-reading config and the hub
      # index — so that is what this restores. SIGHUP, not a restart: the
      # firewall bouncer queries this LAPI per decision, and a restart would
      # drop those queries just to refresh an index.
      systemd.services.crowdsec.serviceConfig.ExecReload = "${getExe' pkgs.coreutils "kill"} -HUP $MAINPID";

      # crowdsec-setup's ExecStartPre runs `cscli hub update`, which needs
      # cdn-hub.crowdsec.net, and the unit is Restart=no — one failed lookup
      # leaves crowdsec down permanently, and netbird-proxy fails *closed* on
      # a dead LAPI, so every published service answers 403. Not hypothetical:
      # on 2026-08-29 a comin switch restarted crowdsec and unbound together,
      # ExecStartPre lost the DNS race by six seconds, crowdsec stayed
      # failed, and jellyfin, immich, grafana, the status page and the knot
      # served 403 for six hours — comin fetches through the same edge, so
      # the fleet could not deploy its way out.
      #
      # Two independent guards, because either alone leaves a way in:
      # after/wants nss-lookup.target (unbound sits Before= it — the ordering
      # that was missing), and Restart=on-failure so a failed update retries
      # at RestartSec instead of leaving the ingress dark.
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
