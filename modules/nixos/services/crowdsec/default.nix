{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.lists) optional;
  inherit (lib.meta) getExe getExe';

  cfg = config.cosmos.services.crowdsec;
in {
  options.cosmos.services.crowdsec = {
    enable = mkEnableOption "crowdsec";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      {
        directory = "/var/lib/crowdsec";
        user = "crowdsec";
        group = "crowdsec";
        mode = "0750";
      }
      {
        directory = "/etc/crowdsec";
        mode = "0755";
      }
      # Don't persist crowdsec-firewall-bouncer-register - let DynamicUser recreate it
      # The bouncer will be re-registered on each boot via the register service
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/crowdsec 0755 crowdsec crowdsec - -"
      "f /var/lib/crowdsec/online_api_credentials.yaml 0750 crowdsec crowdsec - -"
    ];

    sops.secrets."keys/crowdsec/enroll_key" = {
      owner = "crowdsec";
    };

    services.crowdsec = {
      enable = true;
      openFirewall = false;
      autoUpdateService = true;

      # Adds new parsing and detection behaviours
      hub.collections =
        [
          "crowdsecurity/linux"
          "crowdsecurity/auditd"
          "crowdsecurity/iptables"
          "crowdsecurity/linux-lpe"
        ]
        ++ (optional config.services.openssh.enable "crowdsecurity/sshd")
        ++ (optional config.services.traefik.enable "crowdsecurity/traefik");

      hub.parsers = [];
      hub.postOverflows = [];

      # Where to get logs from
      localConfig.acquisitions =
        [
          {
            source = "journalctl";
            journalctl_filter = ["_TRANSPORT=journal"];
            labels.type = "syslog";
          }
          {
            source = "journalctl";
            journalctl_filter = ["_TRANSPORT=syslog"];
            labels.type = "syslog";
          }
          {
            source = "journalctl";
            journalctl_filter = ["_TRANSPORT=stdout"];
            labels.type = "syslog";
          }
          {
            source = "journalctl";
            journalctl_filter = ["_TRANSPORT=kernel"];
            labels.type = "syslog";
          }
          {
            source = "file";
            filenames = [
              "/var/log/audit/*.log"
            ];
            labels.type = "auditd";
          }
        ]
        ++ (
          optional config.services.traefik.enable {
            source = "file";
            filenames = [
              "/var/log/traefik/*.log"
            ];
            labels.type = "traefik";
          }
        );

      # What action to take for alerts
      # TODO: add notifications
      localConfig.profiles = [
        {
          name = "default_ip_remediation";
          decisions = [
            {
              duration = "4h";
              type = "ban";
            }
          ];
          filters = [
            "Alert.Remediation == true && Alert.GetScope() == 'Ip'"
          ];
          notifications = [];
          on_success = "break";
        }
        {
          name = "default_range_remediation";
          decisions = [
            {
              duration = "4h";
              type = "ban";
            }
          ];
          filters = [
            "Alert.Remediation == true && Alert.GetScope() == 'Range'"
          ];
          notifications = [];
          on_success = "break";
        }
        {
          name = "pid_alert";
          filters = [
            "Alert.GetScope() == 'pid'"
          ];
          decisions = [];
          notifications = [];
          on_success = "break";
        }
      ];

      settings.general = {
        plugin_config = {
          user = "crowdsec";
          group = "crowdsec";
        };
        api.server = {
          enable = true;
          listen_uri = "127.0.0.1:8076";
        };
      };

      settings.capi.credentialsFile = "/etc/crowdsec/online_api_credentials.yaml";
      settings.lapi.credentialsFile = "/etc/crowdsec/local_api_credentials.yaml";
      settings.console = {
        tokenFile = config.sops.secrets."keys/crowdsec/enroll_key".path;
        configuration = {
          share_manual_decisions = true;
          share_tainted = true;
          share_custom = true;
          console_management = false;
          share_context = true;
        };
      };
    };

    users.users.${config.services.crowdsec.user}.extraGroups = ["nginx" "auditd" "fossorial"];

    services.crowdsec-firewall-bouncer.enable = true;

    # Fix enroll not working due to erroneous '!' in the nixpkgs module
    systemd.services.crowdsec.serviceConfig.ExecStartPre = let
      cscli = getExe' config.services.crowdsec.package "cscli";
      inherit (config.services.crowdsec.settings.console) tokenFile;
      inherit (config.services.crowdsec) name;
      configFile = (pkgs.formats.yaml {}).generate "crowdsec.yaml" config.services.crowdsec.settings.general;
      enrollScript =
        pkgs.writeShellScriptBin "crowdsec-enroll"
        ''
          if [ -e "${tokenFile}" ]; then
            ${cscli} -c=${configFile} console enroll "$(${lib.getExe' pkgs.coreutils "cat"} ${tokenFile})" --name ${name} || true
          fi
        '';
    in [
      "${getExe enrollScript}"
    ];

    # Fix credential loading issue: bouncer needs to run as crowdsec user to access
    # the API key file created by the registration service
    systemd.services.crowdsec-firewall-bouncer.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "crowdsec";
      Group = "crowdsec";
    };

    # Allow DynamicUser for the register service - it will create its own state directory
    # On impermanence systems, the directory will be recreated and bouncer re-registered
    systemd.services.crowdsec-firewall-bouncer-register.serviceConfig = {
      # Ensure the ExecStartPre checks if we need to delete the old bouncer
      ExecStartPre = lib.mkBefore [
        ''${pkgs.bash}/bin/bash -c "if ${pkgs.coreutils}/bin/test ! -f /var/lib/crowdsec-firewall-bouncer-register/api-key.cred; then /run/current-system/sw/bin/cscli bouncers delete crowdsec-firewall-bouncer || true; fi"''
      ];
    };
  };
}
