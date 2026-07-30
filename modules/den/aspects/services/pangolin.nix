# Pangolin server + traefik (services.pangolin) and the Newt tunnel client
# (services.pangolin.newt, nested). Two aspects sharing the env-file generator.
{...}: let
  # Writes an env file with @NAME@ placeholders, then replaces each with the
  # secret's contents.
  mkGenerator = pkgs: let
    inherit (pkgs.lib.strings) concatMapStringsSep concatStringsSep;
    inherit (pkgs.lib.attrsets) mapAttrsToList attrNames;

    toPlaceHolder = name: "@${name}@";
    mkPlaceholderFile = secrets:
      pkgs.writeText "pangolin.env" ''
        ${concatMapStringsSep "\n"
          (name: "${name}=${toPlaceHolder name}")
          (attrNames secrets)}
      '';
  in
    secrets: path: group:
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
  # Pangolin server + traefik reverse proxy.
  den.aspects.services.pangolin.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.meta) getExe;

    generateEnvironmentFile = mkGenerator pkgs;

    pangolinSecrets = {
      SERVER_SECRET = config.sops.secrets."keys/pangolin/server_secret".path;
    };
    traefikSecrets = {
      CLOUDFLARE_DNS_API_TOKEN = config.sops.secrets."keys/cloudflare/dns".path;
    };

    stateDirectory = "/var/lib/pangolin";
    pangolinEnv = "${stateDirectory}/pangolin.env";
    traefikEnv = "${config.services.traefik.dataDir}/traefik.env";
  in {
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
        app.save_logs = true;
        domains.domain1.prefer_wildcard_cert = true;
        flags = {
          disable_signup_without_invite = true;
          disable_user_create_org = true;
          disable_product_help_banners = true;
          allow_raw_resources = true;
        };
      };
    };

    networking.firewall.allowedUDPPorts = [21820];

    # gerbil dials pangolin's internal API on :3001 the instant systemd calls
    # pangolin "started" — which for a Type=simple unit is immediately, while it
    # is still running database migrations. With the module's Restart=always and
    # no RestartSec it retries every 100ms, burns the default 5-restart limit in
    # under a second and parks in `failed`. traefik has Requires=gerbil, so it
    # then never starts and port 443 stays dead — which is exactly what happened
    # after the 1.21.0 migration.
    #
    # Backing off and dropping the rate limiter lets gerbil wait out the
    # migration instead of giving up during it.
    systemd.services.gerbil = {
      serviceConfig.RestartSec = "5s";
      unitConfig.StartLimitIntervalSec = 0;
    };

    services.traefik = {
      staticConfigOptions.accessLog = {
        filePath = "/var/log/traefik/access.log";
        bufferingSize = 100;
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
  };

  # Newt tunnel client (connects out to a Pangolin server).
  den.aspects.services.pangolin.newt.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str;
    inherit (lib.meta) getExe;

    generateEnvironmentFile = mkGenerator pkgs;

    cfg = config.cosmos.services.pangolin.newt;
    newtEnv = "/run/secrets/newt.env";
  in {
    options.cosmos.services.pangolin.newt = {
      endpoint = mkOption {
        type = str;
        default = "https://pangolin.lvdar.nl";
      };
    };

    config = {
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
        settings = {inherit (cfg) endpoint;};
        environmentFile = newtEnv;
      };
    };
  };
}
