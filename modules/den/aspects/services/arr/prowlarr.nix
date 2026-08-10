# services.arr.prowlarr — indexer manager, feeding the others their searches.
#
# Written out rather than built from mkSimpleArr: nixpkgs runs prowlarr under
# DynamicUser with no way to say where its data lives, so both have to be
# overridden by hand.
{den, ...}: let
  inherit (import ./_lib.nix) vpnVhost;
in {
  den.aspects.services.arr.prowlarr = {
    includes = [den.aspects.services.arr];
    nixos = {
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
        };
        vpn.enable = mkEnableOption "prowlarr vpn";
      };

      config = {
        systemd.tmpfiles.rules = ["d '${cfg.stateDir}' 0700 ${cfg.user} root - -"];
        services.prowlarr = {
          enable = true;
          inherit (cfg) package openFirewall;
          settings.server.port = cfg.port;
        };
        systemd.services.prowlarr.serviceConfig = {
          User = cfg.user;
          Group = "media";
          ExecStart = mkForce "${getExe cfg.package} -nobrowser -data=${cfg.stateDir}";
          ReadWritePaths = [cfg.stateDir];
        };
        networking.firewall = mkIf cfg.openFirewall {allowedTCPPorts = [cfg.port];};
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
        services.nginx.virtualHosts = mkIf cfg.vpn.enable (vpnVhost cfg.port);
      };
    };
  };
}
