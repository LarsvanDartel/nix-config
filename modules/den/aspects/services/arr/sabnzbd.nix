# services.arr.sabnzbd — the usenet client, confined to the VPN namespace.
{den, ...}: let
  inherit (import ./_lib.nix) vpnVhost;
in {
  den.aspects.services.arr.sabnzbd = {
    includes = [den.aspects.services.arr];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkPackageOption;
      inherit (lib.types) str path bool port listOf attrs;
      inherit (lib.modules) mkIf;
      inherit (lib.strings) optionalString concatStringsSep removePrefix;
      inherit (lib.attrsets) recursiveUpdate;
      inherit (lib.lists) imap0;

      cfg-arr = config.cosmos.services.arr;
      cfg = cfg-arr.sabnzbd;

      concatStringsCommaIfExists = stringList:
        optionalString (builtins.length stringList > 0) (concatStringsSep "," stringList);
    in {
      options.cosmos.services.arr.sabnzbd = {
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
        };
        whitelistHostnames = mkOption {
          type = listOf str;
          default = [config.networking.hostName];
        };
        whitelistRanges = mkOption {
          type = listOf str;
          # sabnzbd's `local_ranges`. Left empty it falls back to RFC1918, and
          # NetBird hands peers addresses out of the CGNAT range instead — so
          # once the edge started reaching this over the mesh, every request
          # was "External internet access denied" from sabnzbd itself, well
          # past the point where the network was working.
          #
          # Setting this replaces that fallback rather than extending it, so
          # the private ranges have to be repeated here or the LAN loses
          # access in exchange.
          default = [
            "127.0.0.0/8"
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "100.64.0.0/10"
          ];
        };
        vpn.enable = mkOption {
          type = bool;
          default = false;
        };
        secretFiles = mkOption {
          type = listOf path;
          default = [];
        };
        extraSettings = mkOption {
          type = attrs;
          default = {};
        };
      };

      config = {
        systemd.tmpfiles.rules = [
          "d '${cfg.stateDir}' 0700 ${cfg.user} root - -"
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
          inherit (cfg) package user secretFiles;
          configFile = null;
          allowConfigWrite = false;
          group = "media";
          stateDir = removePrefix "/var/lib/" cfg.stateDir;
          settings =
            recursiveUpdate
            {
              misc = {
                # Inside `misc`, where sabnzbd reads it. At the top level it
                # lands above the first section header and is silently ignored,
                # leaving sabnzbd's own `[misc] inet_exposure = 0` in force —
                # so this had never once taken effect.
                #
                # 4 is "web UI reachable from outside", which is what a service
                # published through the edge needs. Anything lower makes
                # check_access fall through to inspecting X-Forwarded-For, and
                # netbird-proxy quite correctly puts the visitor's public
                # address there, so sabnzbd denied every request that had
                # actually come from a browser. The gate in front is SSO and
                # CrowdSec, not sabnzbd's opinion of the client address.
                inet_exposure = 4;

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
              categories =
                {
                  "*" = {
                    name = "*";
                    order = 0;
                    dir = "";
                    priority = 0;
                  };
                }
                // builtins.listToAttrs (imap0 (index: name: {
                  inherit name;
                  value = {
                    inherit name;
                    order = index + 1;
                    dir = "${cfg-arr.mediaDir}/usenet/${name}";
                    priority = -100;
                  };
                }) ["radarr" "sonarr" "lidarr"]);
            }
            cfg.extraSettings;
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.uiPort];

        systemd.services.sabnzbd.vpnConfinement = mkIf cfg.vpn.enable {
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
        };

        services.nginx.virtualHosts = mkIf cfg.vpn.enable (vpnVhost cfg.uiPort);
      };
    };
  };
}
