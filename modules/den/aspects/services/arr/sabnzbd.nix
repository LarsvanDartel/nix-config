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

          # Without this nixpkgs installs sabnzbd.ini mode 0400, and sabnzbd
          # wants to write its own config constantly — server tuning, quota
          # counters, anything changed in the web UI. Every attempt fails with
          # "Cannot write to INI file", which it reports as an error rather
          # than a warning; nixpkgs' own comment says as much and settles for
          # living with it.
          #
          # Declarative config survives anyway, because the pre-start merge
          # feeds it the live ini *first* and the generated settings second,
          # and later files win. So nix stays authoritative for everything it
          # states, and sabnzbd keeps whatever it wrote that nix does not.
          #
          # The one thing to know: a key nix stops declaring keeps its last
          # runtime value rather than returning to the default, since the ini
          # it is merged onto is now its own previous output.
          allowConfigWrite = true;
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

                # The unpackers themselves. sabnzbd defaults these on, but the
                # whole point here is that unpacking not happening is hard to
                # see from the outside — an unpacked download and a paused one
                # both just look like a directory that is not what you wanted.
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

        services.nginx.virtualHosts = mkIf cfg.vpn.enable (vpnVhost cfg.uiPort);
      };
    };
  };
}
