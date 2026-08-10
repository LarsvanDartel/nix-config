# services.arr.jellyseerr — the request front-end people other than the admin
# actually use. Its own unit, because nixpkgs' runs it under DynamicUser.
{den, ...}: let
  inherit (import ./_lib.nix) vpnVhost;
in {
  den.aspects.services.arr.jellyseerr = {
    includes = [den.aspects.services.arr];
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
