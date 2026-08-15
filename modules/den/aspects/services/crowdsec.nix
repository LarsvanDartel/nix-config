# services.crowdsec — behavioural detection and IP reputation for the edge.
#
# Restored from the Pangolin era, where it read traefik's logs and banned
# through a traefik bouncer. Both of those are gone, so the shape changed:
#
#   detection    nginx's access log (the control plane and the IdP) and the
#                journal (sshd, kernel). netbird-proxy's own access logs are
#                shipped to management over gRPC rather than written to disk,
#                so there is nothing local to parse for the published services
#                — their protection comes from reputation, not behaviour.
#   remediation  two bouncers. The firewall bouncer drops banned addresses in
#                nftables, before TLS, which is what actually sheds crawler
#                load; netbird-proxy queries the same LAPI per request, so a
#                blocked visitor gets an answer rather than a timeout, and
#                decisions apply even to traffic the firewall lets through.
#
# Most of the value here is the community blocklist rather than anything
# detected locally: the traffic in question is opportunistic scanning from
# addresses already burned elsewhere. Enrolling in the console (capi) is what
# turns that on, so the enroll key is not optional garnish.
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

    # The same file the crowdsec module generates for its own `-c` flag.
    # Identical inputs, so identical store path — this is a second reference to
    # one file, not a second copy of it.
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
          # The mesh. Every peer reaches the edge through it, and the reverse
          # proxy's own embedded client is a peer too — banning one would take
          # out the thing doing the banning.
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
          # Brings in base-http-scenarios and http-cve: path traversal, the
          # usual scanner probes, and the CVE payloads that follow them. This
          # is the collection that reads what nginx writes.
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

        # Under the state directory, not /etc/crowdsec. These are written at
        # runtime and have to survive a reboot — losing them re-registers the
        # machine as a fresh console instance — but /etc/crowdsec is an
        # nix-generated symlink tree, and bind-mounting a persistent directory
        # over it hides config.yaml, at which point cscli cannot start at all.
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
      # TLS handshake. This is the half that sheds load rather than merely
      # answering politely.
      services.crowdsec-firewall-bouncer.enable = true;

      # nixpkgs enrols only when the token file is ABSENT — the condition is
      # inverted, so with a real token nothing is ever sent. Until that is
      # fixed upstream, do it here; `console enroll` is idempotent, and
      # failure must not keep the engine down, hence the `|| true`.
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

      # nixpkgs gives the registration service `DynamicUser` and a
      # `StateDirectory` that includes crowdsec's own. systemd then insists on
      # relocating /var/lib/crowdsec under /var/lib/private, which cannot work
      # when impermanence has already bind-mounted it — the migration fails with
      # EBUSY, the unit never runs, no API key is ever written, and the bouncer
      # dies at LoadCredential with a file-not-found. It runs as the crowdsec
      # user regardless, so turning the dynamic allocation off costs nothing.
      systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.DynamicUser =
        lib.mkForce false;

      # Upstream's registration script hard-exits with "Bouncer registered but
      # API key is not present" whenever crowdsec's database still lists the
      # bouncer while the key file it refers to has gone. Those two live in
      # different places — the database under /var/lib/crowdsec/state, the key
      # under /var/lib/crowdsec-firewall-bouncer-register — so anything that
      # loses one but not the other wedges the unit permanently, and there is no
      # branch in the script that recovers.
      #
      # Which is exactly what the first working impermanence rollback did on
      # gaia (2026-08-12): the database survived on /persist, the key did not,
      # and the firewall bouncer stayed down through every subsequent restart.
      # Dropping the stale registration lets the script take its "not
      # registered" branch and mint a fresh key.
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

      # nixpkgs gives the bouncer `Requires=` on that registration service but
      # no `After=`, which is no ordering at all — systemd starts both at once.
      # On the very first boot the bouncer therefore reaches LoadCredential
      # before the API key exists and dies at step CREDENTIALS with a bare
      # "No such file or directory". It works ever after, because by then the
      # key is on disk, which is what makes this such a confusing first deploy.
      systemd.services.crowdsec-firewall-bouncer.after = [
        "crowdsec-firewall-bouncer-register.service"
      ];

      # nixpkgs ends the hub-update timer with
      # `ExecStartPost=systemctl reload crowdsec.service`, but runs the unit as
      # an unprivileged `DynamicUser`. Reloading a system unit is a privileged
      # operation, so polkit refuses it:
      #
      #   systemctl[…]: Failed to reload crowdsec.service: Access denied
      #
      # The update itself succeeds — `cscli hub update` exits 0 and the new
      # index is on disk — so this is purely the notification step failing, and
      # the damage is that the unit goes red on every tick. That drags the whole
      # host to `degraded` and fires the OnFailure ntfy route, which is exactly
      # the kind of standing false alarm that teaches you to ignore the channel.
      #
      # Granting the reload is narrower than the alternatives (dropping the
      # ExecStartPost loses the reload; running the timer as root grants far
      # more): one verb, on one unit, for the user crowdsec already runs as.
      security.polkit.extraConfig = ''
        polkit.addRule(function (action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units"
              && action.lookup("unit") == "crowdsec.service"
              && action.lookup("verb") == "reload"
              && subject.user == "${config.services.crowdsec.user}") {
            return polkit.Result.YES;
          }
        });
      '';
    };
  };
}
