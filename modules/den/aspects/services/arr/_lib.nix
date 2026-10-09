# Shared by the *arr aspects. Underscored so the import-tree leaves it alone:
# a plain expression to `import`, not a flake-parts module.
rec {
  # Confined services bind the namespace side of the bridge (192.168.15.1),
  # unroutable from outside; this proxies the same port in the root namespace.
  vpnVhost = port: {
    "127.0.0.1:${toString port}" = {
      listen = [
        {
          addr = "0.0.0.0";
          inherit port;
        }
      ];
      locations."/" = {
        recommendedProxySettings = true;
        proxyWebsockets = true;
        proxyPass = "http://192.168.15.1:${toString port}";
      };
    };
  };

  # radarr/sonarr/lidarr: only name, port and library dir differ.
  mkSimpleArr = {
    name,
    defaultPort,
    libraryDir,
  }: arr: {
    includes = [arr];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkPackageOption mkEnableOption;
      inherit (lib.types) port path bool str;
      inherit (lib.modules) mkIf;

      cfg-arr = config.cosmos.services.arr;
      cfg = cfg-arr.${name};
    in {
      options.cosmos.services.arr.${name} = {
        package = mkPackageOption pkgs name {};
        port = mkOption {
          type = port;
          default = defaultPort;
        };
        stateDir = mkOption {
          type = path;
          default = "${cfg-arr.stateDir}/${name}";
        };
        openFirewall = mkOption {
          type = bool;
          default = !cfg.vpn.enable;
        };
        user = mkOption {
          type = str;
          default = name;
        };
        vpn.enable = mkEnableOption "${name} vpn";
      };

      config = {
        systemd.tmpfiles.rules = [
          "d '${cfg-arr.mediaDir}/library' 0775 root media - -"
          "d '${cfg-arr.mediaDir}/library/${libraryDir}' 0775 root media - -"
        ];
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = "media";
        };
        services.${name} = {
          enable = true;
          inherit (cfg) package user openFirewall;
          group = "media";
          settings.server.port = cfg.port;
          dataDir = cfg.stateDir;
        };
        systemd.services.${name}.vpnConfinement = mkIf cfg.vpn.enable {
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
        services.nginx.virtualHosts = mkIf cfg.vpn.enable (vpnVhost cfg.port);
      };
    };
  };
}
