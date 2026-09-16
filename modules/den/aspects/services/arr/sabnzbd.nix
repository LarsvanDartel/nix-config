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
      inherit (lib.types) str path bool port listOf attrs enum;
      inherit (lib.modules) mkIf;
      inherit (lib.strings) optionalString concatStringsSep removePrefix;
      inherit (lib.attrsets) recursiveUpdate;
      inherit (lib.lists) imap0;

      cfg-arr = config.cosmos.services.arr;
      cfg = cfg-arr.sabnzbd;

      concatStringsCommaIfExists = stringList:
        optionalString (builtins.length stringList > 0) (concatStringsSep "," stringList);

      # sabnzbd's `pp`, which it stores per category as a number.
      ppValues = {
        none = 0;
        repair = 1;
        unpack = 2;
        delete = 3;
      };
      pp = toString ppValues.${cfg.postProcessing};
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
        postProcessing = mkOption {
          type = enum (builtins.attrNames ppValues);
          default = "delete";
          description = ''
            What to do with a download once it has arrived: nothing, repair it
            with par2, also unpack it, or also delete the archives afterwards.

            This has to be said out loud for every category, including the
            default one. sabnzbd leaves a category's `pp` empty to mean "use
            the default category's", and only ever fills the default in when
            it writes the categories section itself — which it never does here,
            because this config is generated. An empty `pp` then goes through
            `int_conv("")` → 0 → `pp_to_opts(0)` → (repair, unpack, delete) all
            false, so a generated config with categories in it silently turns
            post-processing off altogether. That is why downloads arrived as
            unopened rar sets.
          '';
        };
        whitelistHostnames = mkOption {
          type = listOf str;
          default = [config.networking.hostName];
        };
        whitelistRanges = mkOption {
          type = listOf str;
          # sabnzbd's `local_ranges`. Empty falls back to RFC1918, which
          # excludes NetBird's CGNAT peer range — once the edge reached this
          # over the mesh, sabnzbd itself denied every request. Setting this
          # *replaces* the fallback, so the private ranges must be repeated
          # here or the LAN loses access.
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

          # nixpkgs installs sabnzbd.ini mode 0400, but sabnzbd writes its own
          # config constantly (web UI changes, quota counters) — without this
          # every write fails. Declarative config still wins: the pre-start
          # merge feeds the live ini first and generated settings second, and
          # later files win. Caveat: a key nix stops declaring keeps its last
          # runtime value rather than the default.
          allowConfigWrite = true;
          group = "media";
          stateDir = removePrefix "/var/lib/" cfg.stateDir;
          settings =
            recursiveUpdate
            {
              misc = {
                # Must sit inside `misc` — at top level it lands above the
                # first section header and is silently ignored. 4 = "web UI
                # reachable from outside"; anything lower makes check_access
                # inspect X-Forwarded-For, where netbird-proxy puts the
                # visitor's public address, so sabnzbd denied browser requests.
                # The gate in front is SSO and CrowdSec.
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

                # Defaults-on, but stated explicitly: unpacking silently not
                # happening is indistinguishable from a paused download.
                enable_unrar = 1;
                enable_7zip = 1;
                enable_filejoin = 1;
                enable_tsjoin = 1;
                enable_par_cleanup = 1;
              };
              categories =
                {
                  # The default category, which every other one falls back to
                  # for anything it leaves unset — hence `pp` here above all.
                  "*" = {
                    name = "*";
                    order = 0;
                    dir = "";
                    priority = 0;
                    inherit pp;
                  };
                }
                // builtins.listToAttrs (imap0 (index: name: {
                  inherit name;
                  value = {
                    inherit name pp;
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

        # Room for an NZB POST: radarr uploads NZBs to /api?mode=addfile
        # through this vhost, and a UHD remux NZB runs well past nixpkgs'
        # global 10m client_max_body_size — nginx 413'd exactly the largest
        # releases. Finite (not 0) because the port is published and nginx
        # spools request bodies to disk.
        services.nginx.virtualHosts = mkIf cfg.vpn.enable (lib.mkMerge [
          (vpnVhost cfg.uiPort)
          {
            "127.0.0.1:${toString cfg.uiPort}".extraConfig = ''
              client_max_body_size 256m;
            '';
          }
        ]);
      };
    };
  };
}
