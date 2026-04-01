{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkPackageOption mkOption;
  inherit (lib.types) path bool str port;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.meta) getExe;
  inherit (lib.lists) optional;
  inherit (lib.strings) removePrefix;

  cfg-arr = config.cosmos.services.arr;
  cfg = cfg-arr.seerr;
in {
  options.cosmos.services.arr.seerr = {
    enable = mkEnableOption "seerr";
    package = mkPackageOption pkgs "seerr" {};

    stateDir = mkOption {
      type = path;
      default = "${cfg-arr.stateDir}/seerr";
    };

    port = mkOption {
      type = port;
      default = 5055;
      description = "seerr web-UI port.";
    };

    openFirewall = mkOption {
      type = bool;
      default = !cfg.vpn.enable;
    };

    user = mkOption {
      type = str;
      default = "seerr";
      description = ''
        seerr
      '';
    };

    vpn.enable = mkOption {
      type = bool;
      default = false;
    };

    expose = mkOption {
      type = bool;
      default = false;
      description = "Whether to expose seerr";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.enable -> cfg-arr.enable;
        message = ''
          seerr requires arr to be enabled
        '';
      }
      {
        assertion = cfg.vpn.enable -> cfg-arr.vpn.enable;
        message = ''
          The seerr.vpn.enable option requires the
          arr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = !(cfg.vpn.enable && cfg.expose);
        message = ''
          The seerr.vpn.enable option conflicts with the
          seerr.expose option. You cannot set both.
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${cfg.user} root - -"
    ];

    systemd.services.seerr = {
      description = "seerr, a requests manager for Jellyfin";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      environment = {
        PORT = toString cfg.port;
        CONFIG_DIRECTORY = cfg.stateDir;
      };

      serviceConfig = {
        Type = "exec";
        StateDirectory = removePrefix "/var/lib/" cfg.stateDir;
        DynamicUser = false;
        User = cfg.user;
        Group = "seerr";
        ExecStart = getExe cfg.package;
        Restart = "on-failure";

        # Security
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        PrivateMounts = true;
        ProtectSystem = "strict";
        ReadWritePaths = [cfg.stateDir];
      };
    };

    users = {
      groups."seerr" = {};
      users.${cfg.user} = {
        isSystemUser = true;
        group = "seerr";
      };
    };

    networking.firewall.allowedTCPPorts = optional cfg.openFirewall cfg.port;

    services.nginx = mkMerge [
      (mkIf cfg.expose {
        virtualHosts."seerr.lvdar.nl" = {
          forceSSL = true;
          enableACME = false;
          sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
          sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://127.0.0.1:${builtins.toString cfg.port}";
          };
        };
      })
      (mkIf cfg.vpn.enable {
        virtualHosts."127.0.0.1:${builtins.toString cfg.port}" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.port;
            }
          ];
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://192.168.15.1:${builtins.toString cfg.port}";
          };
        };
      })
    ];

    # Enable and specify VPN namespace to confine service in.
    systemd.services.seerr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = cfg-arr.vpn.name;
    };

    # Port mappings
    vpnNamespaces.${cfg-arr.vpn.name} = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
        }
      ];
    };
  };
}
