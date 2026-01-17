{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption mkPackageOption;
  inherit (lib.types) bool port path str;
  inherit (lib.modules) mkIf mkForce;
  inherit (lib.meta) getExe;

  cfg-arr = config.cosmos.services.arr;
  cfg = cfg-arr.prowlarr;
in {
  options.cosmos.services.arr.prowlarr = {
    enable = mkEnableOption "prowlarr";
    package = mkPackageOption pkgs "prowlarr" {};

    port = mkOption {
      type = port;
      default = 9696;
    };

    stateDir = mkOption {
      type = path;
      default = "${cfg-arr.stateDir}/prowlarr";
    };

    openFirewall = mkOption {
      type = bool;
      default = !cfg.vpn.enable;
    };

    user = mkOption {
      type = str;
      default = "prowlarr";
      description = ''
        Prowlarr user
      '';
    };

    vpn.enable = mkEnableOption "prowlarr vpn";
  };

  config = mkIf (cfg-arr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.enable -> cfg-arr.enable;
        message = ''
          Prowlarr requires arr to be enabled
        '';
      }
      {
        assertion = cfg.vpn.enable -> cfg-arr.vpn.enable;
        message = ''
          The prowlarr.vpn.enable option requires the
          vpn.enable option to be set, but it was not.
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${cfg.user} root - -"
    ];

    services.prowlarr = {
      inherit (cfg) enable package openFirewall;
      settings.server.port = cfg.port;
    };

    systemd.services.prowlarr.serviceConfig = {
      User = cfg.user;
      Group = "media";
      ExecStart = mkForce "${getExe cfg.package} -nobrowser -data=${cfg.stateDir}";
      ReadWritePaths = [cfg.stateDir];
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = "media";
    };

    systemd.services.prowlarr.vpnConfinement = mkIf cfg.vpn.enable {
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
