{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.types) str;
  inherit (lib.strings) concatMapStringsSep concatStringsSep;
  inherit (lib.attrsets) mapAttrsToList attrNames;
  inherit (lib.meta) getExe;

  cfg = config.cosmos.services.pangolin;

  pangolinSecrets = {
    SERVER_SECRET = config.sops.secrets."keys/pangolin/server_secret".path;
  };
  traefikSecrets = {
    CLOUDFLARE_DNS_API_TOKEN = config.sops.secrets."keys/cloudflare/dns".path;
  };

  stateDirectory = "/var/lib/pangolin";
  pangolinEnv = "${stateDirectory}/pangolin.env";
  traefikEnv = "${config.services.traefik.dataDir}/traefik.env";
  newtEnv = "/run/secrets/newt.env";

  toPlaceHolder = name: "@${name}@";
  mkPlaceholderFile = secrets:
    pkgs.writeText "pangolin.env" ''
      ${concatMapStringsSep "\n"
        (name: "${name}=${toPlaceHolder name}")
        (attrNames secrets)}
    '';

  generateEnvironmentFile = secrets: path: group:
    pkgs.writeShellScriptBin "generate-environment-file" ''
      install -m 640 -o root -g ${group} "${mkPlaceholderFile secrets}" "${path}"

      # Replace each placeholder with the actual secret
      ${concatStringsSep "\n" (mapAttrsToList (name: value: ''
          ${pkgs.replace-secret}/bin/replace-secret \
            "${toPlaceHolder name}" \
            "${value}" \
            ${path}
        '')
        secrets)}
    '';
in {
  options.cosmos.services.pangolin = {
    enable = mkEnableOption "pangolin";
    newt = {
      enable = mkEnableOption "newt tunnel";
      endpoint = mkOption {
        type = str;
        default = "https://pangolin.lvdar.nl";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      cosmos.system.impermanence.persist.directories = [
        {
          directory = config.services.pangolin.dataDir;
          user = "pangolin";
          group = "fossorial";
          mode = "0770";
        }
      ];

      systemd.tmpfiles.rules = [
        "d /var/log/traefik 0750 traefik fossorial - -"
      ];

      sops.secrets = {
        "keys/pangolin/server_secret" = {};
        "keys/cloudflare/dns" = {};
      };

      services.pangolin = {
        enable = true;
        baseDomain = "lvdar.nl";
        dashboardDomain = "pangolin.lvdar.nl";
        dnsProvider = "cloudflare";
        letsEncryptEmail = "admin@lvdar.nl";
        openFirewall = true;
        environmentFile = pangolinEnv;
        settings = {
          app = {
            save_logs = true;
          };
          domains.domain1 = {
            prefer_wildcard_cert = true;
          };
        };
      };

      services.traefik = {
        staticConfigOptions = {
          accessLog = {
            filePath = "/var/log/traefik/access.log";
            bufferingSize = 100;
          };
        };
        environmentFiles = [traefikEnv];
      };

      systemd.services.pangolin-env = {
        description = "Generate Pangolin environment files";
        wantedBy = ["pangolin.service" "traefik.service"];
        before = ["pangolin.service" "traefik.service"];

        script = ''
          ${getExe (generateEnvironmentFile pangolinSecrets pangolinEnv "fossorial")}
          ${getExe (generateEnvironmentFile traefikSecrets traefikEnv "fossorial")}
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };
    })
    (mkIf cfg.newt.enable {
      sops.secrets = {
        "keys/newt/secret" = {};
        "keys/newt/id" = {};
      };

      systemd.services.newt-env = {
        description = "Generate Newt environment file";
        wantedBy = ["newt.service"];
        before = ["newt.service"];

        script = ''
          ${getExe (
            generateEnvironmentFile
            {
              NEWT_SECRET = config.sops.secrets."keys/newt/secret".path;
              NEWT_ID = config.sops.secrets."keys/newt/id".path;
            }
            newtEnv
            "root"
          )}
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "root";
        };
      };

      services.newt = {
        enable = true;
        settings = {
          inherit (cfg.newt) endpoint;
        };
        environmentFile = newtEnv;
      };
    })
  ];
}
