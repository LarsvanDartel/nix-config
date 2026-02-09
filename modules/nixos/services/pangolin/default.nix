{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.strings) concatMapStringsSep concatStringsSep;
  inherit (lib.attrsets) mapAttrsToList attrNames;

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

  toPlaceHolder = name: "@${name}@";
  mkPlaceholderFile = secrets:
    pkgs.writeText "pangolin.env" ''
      ${concatMapStringsSep "\n"
        (name: "${name}=${toPlaceHolder name}")
        (attrNames secrets)}
    '';

  generateEnvironmentFile = secrets: path:
    pkgs.writeShellScriptBin "generate-environment-file" ''
      install -m 640 -o root -g fossorial "${mkPlaceholderFile secrets}" "${path}"

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
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      {
        directory = config.services.pangolin.dataDir;
        user = "pangolin";
        group = "fossorial";
        mode = "0770";
      }
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

    services.traefik.environmentFiles = [traefikEnv];

    systemd.services.pangolin-env = {
      description = "Generate Pangolin environment file";
      wantedBy = ["pangolin.service" "traefik.service"];
      before = ["pangolin.service" "traefik.service"];

      script = ''
        ${generateEnvironmentFile pangolinSecrets pangolinEnv}/bin/generate-environment-file
        ${generateEnvironmentFile traefikSecrets traefikEnv}/bin/generate-environment-file
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };
  };
}
