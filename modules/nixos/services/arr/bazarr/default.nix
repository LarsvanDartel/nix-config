{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkOption mkPackageOption mkEnableOption;
  inherit (lib.types) port path bool str;
  inherit (lib.modules) mkIf;

  cfg-arr = config.cosmos.services.arr;
  cfg = cfg-arr.bazarr;
in {
  options.cosmos.services.arr.bazarr = {
    enable = mkEnableOption "bazarr";

    package = mkPackageOption pkgs "bazarr" {};

    port = mkOption {
      type = port;
      default = 6767;
      description = "Port for bazarr to use.";
    };

    stateDir = mkOption {
      type = path;
      default = "${cfg-arr.stateDir}/bazarr";
    };

    openFirewall = mkOption {
      type = bool;
      default = !cfg.vpn.enable;
    };

    user = mkOption {
      type = str;
      default = "bazarr";
      description = ''
        bazarr user
      '';
    };

    vpn.enable = mkEnableOption "bazarr vpn";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.enable -> cfg-arr.enable;
        message = ''
          bazarr requires arr to be enabled
        '';
      }
      {
        assertion = cfg.vpn.enable -> cfg-arr.vpn.enable;
        message = ''
          The bazarr.vpn.enable option requires the
          arr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${cfg.user} root - -"
    ];

    users = {
      users.${cfg.user} = {
        isSystemUser = true;
        group = "media";
      };
    };

    systemd.services.bazarr = {
      description = "bazarr";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "media";
        SyslogIdentifier = "bazarr";
        ExecStart = pkgs.writeShellScript "start-bazarr" ''
          ${pkgs.bazarr}/bin/bazarr \
            --config '${cfg.stateDir}' \
            --port ${toString cfg.port} \
            --no-update True
        '';
        Restart = "on-failure";
        KillSignal = "SIGINT";
        SuccessExitStatus = "0 156";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };

    systemd.services.bazarr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = cfg-arr.vpn.name;
    };

    vpnNamespaces.${cfg-arr.vpn.name} = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.enable {
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
    };
  };
}
