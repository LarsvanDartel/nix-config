{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption mkPackageOption;
  inherit (lib.types) str path bool port listOf;
  inherit (lib.modules) mkIf;
  inherit (lib.strings) optionalString concatStringsSep;

  cfg-arr = config.cosmos.services.arr;
  cfg = cfg-arr.sabnzbd;
in {
  options.cosmos.services.arr.sabnzbd = {
    enable = mkEnableOption "SABnzbd";

    stateDir = mkOption {
      type = path;
      default = "${cfg-arr.stateDir}/sabnzbd";
    };

    package = mkPackageOption pkgs "sabnzbd" {};

    uiPort = mkOption {
      type = port;
      default = 6336;
    };

    openFirewall = mkOption {
      type = bool;
      default = !cfg.vpn.enable;
    };

    user = mkOption {
      type = str;
      default = "sabnzbd";
      description = ''
        sabnzbd user
      '';
    };

    whitelistHostnames = mkOption {
      type = listOf str;
      default = [config.networking.hostName];
    };

    whitelistRanges = mkOption {
      type = listOf str;
      default = [];
    };

    vpn.enable = mkOption {
      type = bool;
      default = false;
    };
  };

  config = let
    concatStringsCommaIfExists = stringList: (
      optionalString (builtins.length stringList > 0) (
        concatStringsSep "," stringList
      )
    );
  in
    mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.enable -> cfg-arr.enable;
          message = ''
            sabnzbg requires arr to be enabled
          '';
        }
        {
          assertion = cfg.vpn.enable -> cfg-arr.vpn.enable;
          message = ''
            The sabnzbd.vpn.enable option requires the
            vpn.enable option to be set, but it was not.
          '';
        }
      ];

      users.users.${cfg.user} = {
        isSystemUser = true;
        group = "media";
      };

      systemd.tmpfiles.rules = [
        "d '${cfg.stateDir}' 0700 ${cfg.user} root - -"

        # Media dirs
        "d '${cfg-arr.mediaDir}/usenet'             0755 ${cfg.user} media - -"
        "d '${cfg-arr.mediaDir}/usenet/.incomplete' 0755 ${cfg.user} media - -"
        "d '${cfg-arr.mediaDir}/usenet/.watch'      0755 ${cfg.user} media - -"
        "d '${cfg-arr.mediaDir}/usenet/manual'      0775 ${cfg.user} media - -"
        "d '${cfg-arr.mediaDir}/usenet/lidarr'      0775 ${cfg.user} media - -"
        "d '${cfg-arr.mediaDir}/usenet/radarr'      0775 ${cfg.user} media - -"
        "d '${cfg-arr.mediaDir}/usenet/sonarr'      0775 ${cfg.user} media - -"
        "d '${cfg-arr.mediaDir}/usenet/readarr'     0775 ${cfg.user} media - -"
      ];

      services.sabnzbd = {
        enable = true;
        inherit (cfg) package user;
        group = "media";
        settings = {
          misc = {
            host =
              if cfg.openFirewall
              then "0.0.0.0"
              else if cfg.vpn.enable
              then "192.168.15.1"
              else "127.0.0.1";
            port = cfg.uiPort;
            download_dir = "${cfg-arr.mediaDir}/usenet/.incomplete";
            complete_dir = "${cfg-arr.mediaDir}/usenet/manual";
            dirscan_dir = "${cfg-arr.mediaDir}/usenet/watch";
            host_whitelist = concatStringsCommaIfExists cfg.whitelistHostnames;
            local_ranges = concatStringsCommaIfExists cfg.whitelistRanges;
            permissions = "775";
          };
        };
      };

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.uiPort];

      # Enable and specify VPN namespace to confine service in.
      systemd.services.sabnzbd.vpnConfinement = mkIf cfg.vpn.enable {
        enable = true;
        vpnNamespace = cfg-arr.vpn.name;
      };

      # Port mappings
      vpnNamespaces.${cfg-arr.vpn.name} = mkIf cfg.vpn.enable {
        portMappings = [
          {
            from = cfg.uiPort;
            to = cfg.uiPort;
          }
        ];
      };

      services.nginx = mkIf cfg.vpn.enable {
        virtualHosts."127.0.0.1:${builtins.toString cfg.uiPort}" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.uiPort;
            }
          ];
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://192.168.15.1:${builtins.toString cfg.uiPort}";
          };
        };
      };
    };
}
