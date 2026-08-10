# services.arr.transmission — the torrent client, normally confined to the VPN
# namespace (cosmos.services.arr.transmission.vpn.enable).
{den, ...}: let
  inherit (import ./_lib.nix) vpnVhost;
in {
  den.aspects.services.arr.transmission = {
    includes = [den.aspects.services.arr];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.modules) mkIf;
      inherit (lib.options) mkEnableOption mkOption mkPackageOption;
      inherit (lib.types) bool path str attrs enum port;

      cfg-arr = config.cosmos.services.arr;
      cfg = cfg-arr.transmission;
    in {
      options.cosmos.services.arr.transmission = {
        package = mkPackageOption pkgs "transmission_4" {};
        stateDir = mkOption {
          type = path;
          default = "${cfg-arr.stateDir}/transmission";
        };
        downloadDir = mkOption {
          type = path;
          default = "${cfg-arr.mediaDir}/torrents";
        };
        openFirewall = mkOption {
          type = bool;
          default = !cfg.vpn.enable;
        };
        vpn.enable = mkOption {
          type = bool;
          default = false;
        };
        flood.enable = mkEnableOption "the flood web-UI for transmission.";
        user = mkOption {
          type = str;
          default = "transmission";
        };
        messageLevel = mkOption {
          type = enum ["none" "critical" "error" "warn" "info" "debug" "trace"];
          default = "warn";
        };
        peerPort = mkOption {
          type = port;
          default = 50000;
        };
        uiPort = mkOption {
          type = port;
          default = 9091;
        };
        credentialsFile = mkOption {
          type = path;
          default = "/dev/null";
        };
        extraSettings = mkOption {
          type = attrs;
          default = {};
        };
      };

      config = {
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = "media";
        };

        systemd.tmpfiles.rules = [
          "d '${cfg.stateDir}'                             0750 ${cfg.user} root - -"
          "d '${cfg.stateDir}/.config'                     0750 ${cfg.user} root - -"
          "d '${cfg.stateDir}/.config/transmission-daemon' 0750 ${cfg.user} root - -"
          "d '${cfg.downloadDir}'             0755 ${cfg.user} media - -"
          "d '${cfg.downloadDir}/.incomplete' 0755 ${cfg.user} media - -"
          "d '${cfg.downloadDir}/.watch'      0755 ${cfg.user} media - -"
          "d '${cfg.downloadDir}/manual'      0755 ${cfg.user} media - -"
          "d '${cfg.downloadDir}/lidarr'      0755 ${cfg.user} media - -"
          "d '${cfg.downloadDir}/radarr'      0755 ${cfg.user} media - -"
          "d '${cfg.downloadDir}/sonarr'      0755 ${cfg.user} media - -"
          "d '${cfg.downloadDir}/readarr'     0755 ${cfg.user} media - -"
        ];

        systemd.services.transmission.serviceConfig.IOSchedulingPriority = 7;

        services.transmission = {
          enable = true;
          user = cfg.user;
          group = "media";
          home = cfg.stateDir;
          webHome =
            if cfg.flood.enable
            then pkgs.flood-for-transmission
            else null;
          package = cfg.package;
          openFirewall = cfg.openFirewall;
          openRPCPort = cfg.openFirewall;
          openPeerPorts = cfg.openFirewall;
          credentialsFile = cfg.credentialsFile;
          settings =
            {
              download-dir = cfg.downloadDir;
              incomplete-dir-enabled = true;
              incomplete-dir = "${cfg.downloadDir}/.incomplete";
              watch-dir-enabled = true;
              watch-dir = "${cfg.downloadDir}/.watch";
              umask = "002";
              rpc-bind-address =
                if cfg.vpn.enable
                then "192.168.15.1"
                else "0.0.0.0";
              rpc-port = cfg.uiPort;
              rpc-whitelist-enabled = true;
              rpc-whitelist = "127.0.0.1,192.168.*,10.*";
              rpc-authentication-required = false;
              blocklist-enabled = true;
              blocklist-url = "https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz";
              peer-port = cfg.peerPort;
              utp-enabled = false;
              encryption = 1;
              port-forwarding-enabled = false;
              anti-brute-force-enabled = true;
              anti-brute-force-threshold = 10;
              message-level =
                {
                  none = 0;
                  critical = 1;
                  error = 2;
                  warn = 3;
                  info = 4;
                  debug = 5;
                  trace = 6;
                }
                .${
                  cfg.messageLevel
                };
            }
            // cfg.extraSettings;
        };

        systemd.services.transmission.vpnConfinement = mkIf cfg.vpn.enable {
          enable = true;
          vpnNamespace = cfg-arr.vpn.name;
        };

        vpnNamespaces.${cfg-arr.vpn.name} = mkIf cfg.vpn.enable {
          portMappings = [
            {
              from = cfg.uiPort;
              to = cfg.uiPort;
            }
          ];
          openVPNPorts = [
            {
              port = cfg.peerPort;
              protocol = "both";
            }
          ];
        };

        services.nginx.virtualHosts = mkIf cfg.vpn.enable (vpnVhost cfg.uiPort);
      };
    };
  };
}
