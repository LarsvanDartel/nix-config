{
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
    enable = mkOption {
      type = bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Transmission service.
      '';
    };

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
      description = "Open firewall for `peer-port` and `rpc-port`.";
    };

    vpn.enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Route Transmission traffic through the VPN.
      '';
    };

    flood.enable = mkEnableOption "the flood web-UI for the transmission web-UI.";

    user = mkOption {
      type = str;
      default = "transmission";
      description = ''
        Transmisson user
      '';
    };

    messageLevel = mkOption {
      type = enum [
        "none"
        "critical"
        "error"
        "warn"
        "info"
        "debug"
        "trace"
      ];
      default = "warn";
      example = "debug";
      description = "Sets the message level of transmission.";
    };

    peerPort = mkOption {
      type = port;
      default = 50000;
      description = "Transmission peer traffic port.";
    };

    uiPort = mkOption {
      type = port;
      default = 9091;
      description = "Transmission web-UI port.";
    };

    credentialsFile = mkOption {
      type = path;
      description = ''
        Path to a JSON file to be merged with the settings.
        Useful to merge a file which is better kept out of the Nix store
        to set secret config parameters like `rpc-password`.
      '';
      default = "/dev/null";
      example = "/var/lib/secrets/transmission/settings.json";
    };

    extraSettings = mkOption {
      type = attrs;
      default = {};
      example = {
        trash-original-torrent-files = true;
      };
      description = ''
        Extra config settings for the Transmission service.

        See the `services.transmission.settings` nixos options in
        the relevant section of the `configuration.nix` manual or on
        [search.nixos.org](https://search.nixos.org/options?channel=unstable&query=services.transmission.settings).
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.enable -> cfg-arr.enable;
        message = ''
          Transmisson requires arr to be enabled
        '';
      }
    ];
    users = {
      users.${cfg.user} = {
        isSystemUser = true;
        group = "media";
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}'                             0750 ${cfg.user} root - -"
      "d '${cfg.stateDir}/.config'                     0750 ${cfg.user} root - -"
      "d '${cfg.stateDir}/.config/transmission-daemon' 0750 ${cfg.user} root - -"

      # Media Dirs
      "d '${cfg.downloadDir}'             0755 ${cfg.user} media - -"
      "d '${cfg.downloadDir}/.incomplete' 0755 ${cfg.user} media - -"
      "d '${cfg.downloadDir}/.watch'      0755 ${cfg.user} media - -"
      "d '${cfg.downloadDir}/manual'      0755 ${cfg.user} media - -"
      "d '${cfg.downloadDir}/lidarr'      0755 ${cfg.user} media - -"
      "d '${cfg.downloadDir}/radarr'      0755 ${cfg.user} media - -"
      "d '${cfg.downloadDir}/sonarr'      0755 ${cfg.user} media - -"
      "d '${cfg.downloadDir}/readarr'     0755 ${cfg.user} media - -"
    ];

    systemd.services.transmission.serviceConfig = {
      IOSchedulingPriority = 7;
    };

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
            if cfg.messageLevel == "none"
            then 0
            else if cfg.messageLevel == "critical"
            then 1
            else if cfg.messageLevel == "error"
            then 2
            else if cfg.messageLevel == "warn"
            then 3
            else if cfg.messageLevel == "info"
            then 4
            else if cfg.messageLevel == "debug"
            then 5
            else if cfg.messageLevel == "trace"
            then 6
            else null;
        }
        // cfg.extraSettings;
    };

    systemd.services.transmission.vpnConfinement = mkIf cfg.vpn.enable {
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
      openVPNPorts = [
        {
          port = cfg.peerPort;
          protocol = "both";
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
