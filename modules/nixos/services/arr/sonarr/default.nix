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
  cfg = cfg-arr.sonarr;
in {
  options.cosmos.services.arr.sonarr = {
    enable = mkEnableOption "sonarr";

    package = mkPackageOption pkgs "sonarr" {};

    port = mkOption {
      type = port;
      default = 8989;
      description = "Port for sonarr to use.";
    };

    stateDir = mkOption {
      type = path;
      default = "${cfg-arr.stateDir}/sonarr";
    };

    openFirewall = mkOption {
      type = bool;
      default = !cfg.vpn.enable;
    };

    user = mkOption {
      type = str;
      default = "sonarr";
      description = ''
        sonarr user
      '';
    };

    vpn.enable = mkEnableOption "sonarr vpn";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.enable -> cfg-arr.enable;
        message = ''
          sonarr requires arr to be enabled
        '';
      }
      {
        assertion = cfg.vpn.enable -> cfg-arr.vpn.enable;
        message = ''
          The sonarr.vpn.enable option requires the
          arr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg-arr.mediaDir}/library'        0775 root media - -"
      "d '${cfg-arr.mediaDir}/library/shows'  0775 root media - -"
    ];

    users = {
      users.${cfg.user} = {
        isSystemUser = true;
        group = "media";
      };
    };

    services.sonarr = {
      enable = true;
      inherit (cfg) package user openFirewall;
      group = "media";
      settings.server.port = cfg.port;
      dataDir = cfg.stateDir;
    };

    systemd.services.sonarr.vpnConfinement = mkIf cfg.vpn.enable {
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
