# Shared by the *arr aspects, which each live in their own file. Underscored,
# so import-tree leaves it alone and it stays a plain expression to `import`
# rather than a flake-parts module.
rec {
  # nginx vhost fronting a service inside the VPN namespace.
  #
  # A confined service binds the namespace side of the bridge (192.168.15.1),
  # which nothing outside the namespace can route to. This listens on the same
  # port in the root namespace and proxies across, so the port means the same
  # thing whether or not a service happens to be confined.
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

  # radarr, sonarr and lidarr are the same service three times over: the same
  # nixpkgs module shape, the same options, differing only in name, port and
  # which library directory they own. Written out per file they were 70
  # identical lines apiece, where the only thing worth reading is the three
  # values below — so each file supplies those and this supplies the rest.
  #
  # Anything that grows its own shape (prowlarr's ExecStart override, bazarr's
  # hand-rolled unit) is written out longhand in its own file instead.
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
