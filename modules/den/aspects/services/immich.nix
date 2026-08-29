# services.immich
{...}: {
  den.aspects.services.immich.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf path str;

    cfg = config.cosmos.services.immich;
  in {
    options.cosmos.services.immich = {
      mediaDir = mkOption {
        type = str;
        default = "/var/lib/immich";
      };

      accelerationDevices = mkOption {
        type = listOf path;
        default = ["/dev/dri/renderD128"];
        description = ''
          Render nodes to hand immich's transcoder.

          Which card this is, is a fact about the host, so a host with more
          than one GPU should name its by-path symlink here — renderD12x
          numbering follows probe order and moves between cards when one fails
          to bind. See the same option on services.transcode.
        '';
      };
    };

    config = {
      systemd.tmpfiles.rules = ["d '${cfg.mediaDir}' 0775 immich media - -"];
      cosmos.system.impermanence.persist.directories = [
        {
          directory = "/var/lib/immich";
          user = "immich";
          group = "media";
          mode = "0750";
        }
        {
          # postgresql, not postgres. The directory read this way for months
          # and it never mattered, because the initrd rollback was also broken
          # (see core/impermanence.nix) — so nothing was wiping the root
          # subvolume that the real PGDATA was sitting on. The two bugs cancelled
          # out, and fixing the rollback first would have destroyed the immich
          # database on the next boot.
          #
          # Lives here rather than in a postgres aspect because immich is the
          # only thing on this host that uses postgres at all.
          directory = "/var/lib/postgresql";
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

      sops.secrets."keys/immich/oauth-client-secret".owner = "kanidm";
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
        inherit (cfg) accelerationDevices;
        user = "immich";
        group = "media";
      };
    };
  };
}
