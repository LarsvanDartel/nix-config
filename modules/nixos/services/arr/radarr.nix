{config, ...}: let
  inherit (config.flake.modules.nixos) arr;
in {
  flake.modules.nixos.radarr = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkPackageOption mkEnableOption;
    inherit (lib.types) port path bool str;
    inherit (lib.modules) mkIf;

    cfg-arr = config.cosmos.services.arr;
    cfg = cfg-arr.radarr;
  in {
    imports = [arr];

    options.cosmos.services.arr.radarr = {
      package = mkPackageOption pkgs "radarr" {};

      port = mkOption {
        type = port;
        default = 7878;
        description = "Port for Radarr to use.";
      };

      stateDir = mkOption {
        type = path;
        default = "${cfg-arr.stateDir}/radarr";
      };

      openFirewall = mkOption {
        type = bool;
        default = !cfg.vpn.enable;
      };

      user = mkOption {
        type = str;
        default = "radarr";
        description = ''
          Radarr user
        '';
      };

      vpn.enable = mkEnableOption "radarr vpn";
    };

    config = {
      systemd.tmpfiles.rules = [
        "d '${cfg-arr.mediaDir}/library'        0775 root media - -"
        "d '${cfg-arr.mediaDir}/library/movies' 0775 root media - -"
      ];

      users = {
        users.${cfg.user} = {
          isSystemUser = true;
          group = "media";
        };
      };

      services.radarr = {
        enable = true;
        inherit (cfg) package user openFirewall;
        group = "media";
        settings.server.port = cfg.port;
        dataDir = cfg.stateDir;
      };

      systemd.services.radarr.vpnConfinement = mkIf cfg.vpn.enable {
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
  };
}
