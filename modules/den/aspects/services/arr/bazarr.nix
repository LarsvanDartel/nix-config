# services.arr.bazarr — subtitles for whatever radarr and sonarr fetched.
#
# The unit is hand-rolled rather than nixpkgs': that module has no way to place
# the config directory, and bazarr keeps its database there.
{den, ...}: let
  inherit (import ./_lib.nix) vpnVhost;
in {
  den.aspects.services.arr.bazarr = {
    includes = [den.aspects.services.arr];
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
      cfg = cfg-arr.bazarr;
    in {
      options.cosmos.services.arr.bazarr = {
        package = mkPackageOption pkgs "bazarr" {};
        port = mkOption {
          type = port;
          default = 6767;
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
        };
        vpn.enable = mkEnableOption "bazarr vpn";
      };

      config = {
        systemd.tmpfiles.rules = ["d '${cfg.stateDir}' 0700 ${cfg.user} root - -"];
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = "media";
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
        networking.firewall = mkIf cfg.openFirewall {allowedTCPPorts = [cfg.port];};
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
        services.nginx.virtualHosts = mkIf cfg.vpn.enable (vpnVhost cfg.port);
      };
    };
  };
}
