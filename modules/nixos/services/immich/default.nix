{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) str;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.immich;
in {
  options.cosmos.services.immich = {
    enable = mkEnableOption "immich";
    mediaDir = mkOption {
      type = str;
      default = "/var/lib/immich";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d '${cfg.mediaDir}' 0775 immich media - -"
    ];
    cosmos.system.impermanence.persist.directories = [
      {
        directory = "/var/lib/immich";
        user = "immich";
        group = "media";
        mode = "0750";
      }
      {
        directory = "/var/lib/postgres";
        user = "postgres";
        group = "postgres";
        mode = "0750";
      }
      {
        directory = "/var/lib/redis-immich";
        user = "redis-immich";
        group = "redis-immich";
        mode = "0750";
      }
    ];

    sops.secrets."keys/immich/oauth-client-secret" = {
      owner = "kanidm";
    };
    services.immich = {
      enable = true;
      host = "0.0.0.0";
      mediaLocation = cfg.mediaDir;
      settings = {
        server.externalDomain = "https://immich.lvdar.nl";
        oauth = {
          enabled = true;
          autoLaunch = true;
          buttonText = "Login with Kanidm";
          clientId = "immich";
          clientSecret._secret = config.sops.secrets."keys/immich/oauth-client-secret".path;
          issuerUrl = "https://auth.lvdar.nl/oauth2/openid/immich";
          roleClaim = "immich_groups";
          signingAlgorithm = "ES256";
        };
        passwordLogin.enabled = false;
      };
      accelerationDevices = ["/dev/dri/renderD128"];
      user = "immich";
      group = "media";
    };
  };
}
