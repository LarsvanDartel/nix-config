# The *arr stack. `services.arr` is the base (media group + shared options); each
# child aspect includes it. `services.arr-vpn` adds the VPN-confinement namespace.
{
  den,
  inputs,
  ...
}: let
  arr = den.aspects.services.arr;

  # nginx reverse-proxy vhost for a VPN-confined service (proxies the namespace IP).
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
in {
  flake-file.inputs.vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

  # Base: media group + shared media/state dirs.
  den.aspects.services.arr.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) path;

    cfg = config.cosmos.services.arr;
  in {
    options.cosmos.services.arr = {
      mediaDir = mkOption {
        type = path;
        default = "/data/media";
      };
      stateDir = mkOption {
        type = path;
        default = "/data/.state/arr";
      };
    };

    config = {
      users.groups.media = {};
      cosmos.user.extraGroups = ["media"];
      systemd.tmpfiles.rules = ["d '${cfg.mediaDir}'  0775 root media - -"];
    };
  };

  # VPN confinement namespace + optional test service.
  den.aspects.services.arr.vpn = {
    includes = [arr];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkEnableOption mkOption;
      inherit (lib.modules) mkIf;
      inherit (lib.types) nullOr path listOf str port;
      inherit (lib.lists) optional;
      inherit (lib.meta) getExe;

      cfg = config.cosmos.services.arr.vpn;
    in {
      imports = [inputs.vpn-confinement.nixosModules.default];

      options.cosmos.services.arr.vpn = {
        name = mkOption {
          type = str;
          default = "wg";
        };
        configFile = mkOption {
          type = nullOr path;
          default = null;
        };
        postUp = mkOption {
          type = str;
          default = "";
        };
        accessibleFrom = mkOption {
          type = listOf str;
          default = [];
        };
        vpnTestService = {
          enable = mkEnableOption "the vpn test service";
          port = mkOption {
            type = nullOr port;
            default = null;
          };
        };
        openTcpPorts = mkOption {
          type = listOf port;
          default = [];
        };
        openUdpPorts = mkOption {
          type = listOf port;
          default = [];
        };
      };

      config = {
        assertions = [
          {
            assertion = cfg.configFile != null;
            message = "The arr.vpn feature requires cosmos.services.arr.vpn.configFile to be set.";
          }
        ];

        vpnNamespaces.${cfg.name} = {
          enable = true;
          openVPNPorts = optional (cfg.vpnTestService.port != null) {
            port = cfg.vpnTestService.port;
            protocol = "tcp";
          };
          # Every entry becomes a route inside the namespace, back out through
          # the bridge. Anything not listed is answered via the namespace's
          # default route — which is the tunnel — so the reply leaves through
          # the VPN and is never seen again.
          #
          # That is what made sabnzbd and transmission unreachable from the
          # mesh while working locally: their ports are DNAT'd into the
          # namespace in prerouting, so a request from gaia arrived fine and
          # the SYN/ACK went out of ProtonVPN. It presented as a plain timeout
          # with the packet absent from both hosts' filter chains, because
          # prerouting had already redirected it and the reply never came back.
          accessibleFrom =
            [
              "192.168.1.0/24"
              "192.168.0.0/24"
              "127.0.0.1"
              # NetBird's peer range, so the edge can reach these at all.
              "100.64.0.0/10"
            ]
            ++ cfg.accessibleFrom;
          wireguardConfigFile = cfg.configFile;
        };

        systemd.services.arr.postStart = cfg.postUp;

        # VPN-Confinement pings the WireGuard endpoint before configuring the
        # tunnel and gives up after five attempts, one second apart. That is
        # not enough at boot: network-online.target is reached when dhcpcd has
        # a lease, which is a while before the WAN actually carries traffic, so
        # arr-up ran into a dead network, failed, and took sabnzbd and
        # transmission — both BindsTo it — down with it until someone noticed.
        #
        # Type=oneshot forbids Restart=, so the unit cannot simply try again.
        # Waiting for the same precondition it does, with a budget measured in
        # minutes rather than seconds, means its own check then passes first
        # try. Parsing the endpoint out of the config here rather than pinging
        # something well-known keeps this honest: the thing waited for is
        # exactly the thing needed next.
        systemd.services.arr.serviceConfig.ExecStartPre = [
          (getExe (pkgs.writeShellApplication {
            name = "arr-wait-for-endpoint";
            runtimeInputs = with pkgs; [gnugrep gnused iputils];
            text = ''
              endpoint="$(grep -iE '^[[:space:]]*Endpoint[[:space:]]*=' ${cfg.configFile} \
                | head -n1 | sed -E 's/.*=[[:space:]]*//; s/[[:space:]]*$//')"
              # Strip the port; bracketed for IPv6, bare otherwise.
              host="$(sed -E 's/^\[(.*)\]:[0-9]+$/\1/; s/^([^]]*):[0-9]+$/\1/' <<<"$endpoint")"

              if [ -z "$host" ]; then
                echo "arr: no Endpoint in the wireguard config; leaving the wait to vpn-up" >&2
                exit 0
              fi

              echo -n "arr: waiting for wireguard endpoint '$host'"
              for _ in $(seq 1 120); do
                if ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
                  echo " reachable"
                  exit 0
                fi
                echo -n .
                sleep 1
              done

              # Not fatal on its own: the network may be up while ICMP is
              # dropped, and vpn-up's own check is still to come. Failing here
              # would turn a slow boot into the very outage this prevents.
              echo
              echo "arr: endpoint '$host' still unreachable after 120s; continuing anyway" >&2
            '';
          }))
        ];

        systemd.services.vpn-test-service = mkIf cfg.vpnTestService.enable {
          enable = true;
          vpnConfinement = {
            enable = true;
            vpnNamespace = cfg.name;
          };
          script = let
            vpn-test = pkgs.writeShellApplication {
              name = "vpn-test";
              runtimeInputs = with pkgs; [util-linux unixtools.ping coreutils curl bash libressl netcat-gnu openresolv dig];
              text =
                ''
                  cd "$(mktemp -d)"
                  dig google.com
                  echo "/etc/resolv.conf contains:"
                  cat /etc/resolv.conf
                  echo "resolvconf output:"
                  resolvconf -l
                  echo ""
                  echo "Getting IP:"
                  curl -s ipinfo.io
                  echo -ne "DNS leak test:"
                  curl -s https://raw.githubusercontent.com/macvk/dnsleaktest/b03ab54d574adbe322ca48cbcb0523be720ad38d/dnsleaktest.sh -o dnsleaktest.sh
                  chmod +x dnsleaktest.sh
                  ./dnsleaktest.sh
                ''
                + (
                  if cfg.vpnTestService.port != null
                  then ''
                    echo "starting netcat on port ${toString cfg.vpnTestService.port}:"
                    nc -vnlp ${toString cfg.vpnTestService.port}
                  ''
                  else ""
                );
            };
          in "${vpn-test}/bin/vpn-test";
        };
      };
    };
  };

  # Simple *arr services (radarr/sonarr/lidarr share the same shape).
  den.aspects.services.arr.radarr = {
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
      cfg = cfg-arr.radarr;
    in {
      options.cosmos.services.arr.radarr = {
        package = mkPackageOption pkgs "radarr" {};
        port = mkOption {
          type = port;
          default = 7878;
        };
        stateDir = mkOption {
          type = path;
          default = "${cfg-arr.stateDir}/radarr";
        };
        openFirewall = mkOption {
          type = bool;
          default = !cfg.vpn.enable;
        };
        user = mkOption {
          type = str;
          default = "radarr";
        };
        vpn.enable = mkEnableOption "radarr vpn";
      };

      config = {
        systemd.tmpfiles.rules = [
          "d '${cfg-arr.mediaDir}/library'        0775 root media - -"
          "d '${cfg-arr.mediaDir}/library/movies' 0775 root media - -"
        ];
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = "media";
        };
        services.radarr = {
          enable = true;
          inherit (cfg) package user openFirewall;
          group = "media";
          settings.server.port = cfg.port;
          dataDir = cfg.stateDir;
        };
        systemd.services.radarr.vpnConfinement = mkIf cfg.vpn.enable {
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

  den.aspects.services.arr.sonarr = {
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
      cfg = cfg-arr.sonarr;
    in {
      options.cosmos.services.arr.sonarr = {
        package = mkPackageOption pkgs "sonarr" {};
        port = mkOption {
          type = port;
          default = 8989;
        };
        stateDir = mkOption {
          type = path;
          default = "${cfg-arr.stateDir}/sonarr";
        };
        openFirewall = mkOption {
          type = bool;
          default = !cfg.vpn.enable;
        };
        user = mkOption {
          type = str;
          default = "sonarr";
        };
        vpn.enable = mkEnableOption "sonarr vpn";
      };

      config = {
        systemd.tmpfiles.rules = [
          "d '${cfg-arr.mediaDir}/library'        0775 root media - -"
          "d '${cfg-arr.mediaDir}/library/shows'  0775 root media - -"
        ];
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = "media";
        };
        services.sonarr = {
          enable = true;
          inherit (cfg) package user openFirewall;
          group = "media";
          settings.server.port = cfg.port;
          dataDir = cfg.stateDir;
        };
        systemd.services.sonarr.vpnConfinement = mkIf cfg.vpn.enable {
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

  den.aspects.services.arr.lidarr = {
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
      cfg = cfg-arr.lidarr;
    in {
      options.cosmos.services.arr.lidarr = {
        package = mkPackageOption pkgs "lidarr" {};
        port = mkOption {
          type = port;
          default = 8686;
        };
        stateDir = mkOption {
          type = path;
          default = "${cfg-arr.stateDir}/lidarr";
        };
        openFirewall = mkOption {
          type = bool;
          default = !cfg.vpn.enable;
        };
        user = mkOption {
          type = str;
          default = "lidarr";
        };
        vpn.enable = mkEnableOption "lidarr vpn";
      };

      config = {
        systemd.tmpfiles.rules = [
          "d '${cfg-arr.mediaDir}/library'        0775 root media - -"
          "d '${cfg-arr.mediaDir}/library/music'  0775 root media - -"
        ];
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = "media";
        };
        services.lidarr = {
          enable = true;
          inherit (cfg) package user openFirewall;
          group = "media";
          settings.server.port = cfg.port;
          dataDir = cfg.stateDir;
        };
        systemd.services.lidarr.vpnConfinement = mkIf cfg.vpn.enable {
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

  den.aspects.services.arr.prowlarr = {
    includes = [arr];
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

  den.aspects.services.arr.bazarr = {
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

  den.aspects.services.arr.transmission = {
    includes = [arr];
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

  den.aspects.services.arr.sabnzbd = {
    includes = [arr];
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
                    dir = "/tank/media/usenet/${name}";
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

  den.aspects.services.arr.jellyseerr = {
    includes = [arr];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkPackageOption;
      inherit (lib.types) path bool str port;
      inherit (lib.modules) mkIf mkMerge;
      inherit (lib.meta) getExe;
      inherit (lib.lists) optional;
      inherit (lib.strings) removePrefix;

      cfg-arr = config.cosmos.services.arr;
      cfg = cfg-arr.seerr;
    in {
      options.cosmos.services.arr.seerr = {
        package = mkPackageOption pkgs "seerr" {};
        stateDir = mkOption {
          type = path;
          default = "${cfg-arr.stateDir}/seerr";
        };
        port = mkOption {
          type = port;
          default = 5055;
        };
        openFirewall = mkOption {
          type = bool;
          default = !cfg.vpn.enable;
        };
        user = mkOption {
          type = str;
          default = "seerr";
        };
        vpn.enable = mkOption {
          type = bool;
          default = false;
        };
        expose = mkOption {
          type = bool;
          default = false;
        };
      };

      config = {
        assertions = [
          {
            assertion = !(cfg.vpn.enable && cfg.expose);
            message = "seerr.vpn.enable conflicts with seerr.expose.";
          }
        ];

        systemd.tmpfiles.rules = ["d '${cfg.stateDir}' 0700 ${cfg.user} root - -"];

        systemd.services.seerr = {
          description = "seerr, a requests manager for Jellyfin";
          after = ["network.target"];
          wantedBy = ["multi-user.target"];
          environment = {
            PORT = toString cfg.port;
            CONFIG_DIRECTORY = cfg.stateDir;
          };
          serviceConfig = {
            Type = "exec";
            StateDirectory = removePrefix "/var/lib/" cfg.stateDir;
            DynamicUser = false;
            User = cfg.user;
            Group = "seerr";
            ExecStart = getExe cfg.package;
            Restart = "on-failure";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectHostname = true;
            ProtectClock = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            NoNewPrivileges = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            RemoveIPC = true;
            PrivateMounts = true;
            ProtectSystem = "strict";
            ReadWritePaths = [cfg.stateDir];
          };
        };

        users.groups.seerr = {};
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = "seerr";
        };

        networking.firewall.allowedTCPPorts = optional cfg.openFirewall cfg.port;

        services.nginx.virtualHosts = mkMerge [
          (mkIf cfg.expose {
            "seerr.lvdar.nl" = {
              forceSSL = true;
              enableACME = false;
              sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
              sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";
              locations."/" = {
                recommendedProxySettings = true;
                proxyWebsockets = true;
                proxyPass = "http://127.0.0.1:${toString cfg.port}";
              };
            };
          })
          (mkIf cfg.vpn.enable (vpnVhost cfg.port))
        ];

        systemd.services.seerr.vpnConfinement = mkIf cfg.vpn.enable {
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
      };
    };
  };
}
