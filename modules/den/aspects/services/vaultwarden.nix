# services.vaultwarden — Bitwarden-compatible password vault; login via kanidm SSO.
#
# Ungated: Bitwarden clients can't follow the NetBird gate's redirect. SSO_ONLY
# makes kanidm the only way in, and its `vaultwarden-users` scope map is the
# signup gate; the master password still unlocks (and encrypts) the vault.
{
  den,
  inputs,
  ...
}: {
  den.aspects.services.vaultwarden = {
    includes = [den.aspects.services.netbird.client];

    kanidm-provision = {config, ...}: let
      cfg = config.cosmos.services.vaultwarden;
    in {
      # The only signup gate (SSO_ONLY below).
      groups.vaultwarden-users = {
        overwriteMembers = false;
        members = ["lvdar"];
      };
      oauth2.vaultwarden = {
        displayName = "Vaultwarden";
        # Bitwarden clients go through vaultwarden's own callback, so this is
        # the only redirect kanidm ever sees.
        originUrl = ["https://${cfg.domain}/identity/connect/oidc-signin"];
        originLanding = "https://${cfg.domain}";
        basicSecret = "keys/vaultwarden/oauth-client-secret";
        preferShortUsername = true;
        scopeMaps.vaultwarden-users = ["openid" "profile" "email"];
      };
    };

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.vaultwarden;
      backupDir = "/var/backup/vaultwarden";
    in {
      options.cosmos.services.vaultwarden = {
        port = mkOption {
          type = port;
          default = 8222;
        };

        domain = mkOption {
          type = str;
          default = "vault.lvdar.nl";
          description = "Public name. Must match the published service on gaia.";
        };

        authDomain = mkOption {
          type = str;
          default = "auth.lvdar.nl";
          description = "kanidm's public origin.";
        };
      };

      config = {
        # Shared with kanidm's host (services/kanidm.nix), hence hosts/common.
        sops.secrets."keys/vaultwarden/oauth-client-secret".sopsFile =
          builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";
        sops.templates."vaultwarden.env".content = ''
          SSO_CLIENT_SECRET=${config.sops.placeholder."keys/vaultwarden/oauth-client-secret"}
        '';

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/vaultwarden";
            user = "vaultwarden";
            group = "vaultwarden";
            mode = "0700";
          }
          {
            directory = backupDir;
            user = "vaultwarden";
            group = "vaultwarden";
            mode = "0700";
          }
        ];

        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        services.vaultwarden = {
          enable = true;
          dbBackend = "sqlite";
          inherit (cfg) domain;
          # Nightly sqlite .backup (23:00, before restic at 02:00), so restic
          # copies a consistent DB without stopping the service.
          inherit backupDir;
          environmentFile = config.sops.templates."vaultwarden.env".path;

          config = {
            ROCKET_ADDRESS =
              if config.cosmos.networking.edgeTerminated
              then "0.0.0.0"
              else "127.0.0.1";
            ROCKET_PORT = cfg.port;

            # No ADMIN_TOKEN: the /admin page stays disabled.
            SIGNUPS_ALLOWED = false;

            SSO_ENABLED = true;
            SSO_ONLY = true;
            SSO_AUTHORITY = "https://${cfg.authDomain}/oauth2/openid/vaultwarden";
            SSO_CLIENT_ID = "vaultwarden";
            # Vaultwarden keeps its own session (7-day idle refresh) instead of
            # following kanidm's tokens, so a kanidm outage doesn't log clients
            # out; kanidm is only needed to log in.
            SSO_AUTH_ONLY_NOT_SESSION = true;

            # gaia's Stalwart mesh relay (services/stalwart.nix): no auth or
            # STARTTLS offered; hand-synced with gaia.nix relayClients.
            SMTP_HOST = "gaia.nb.lvdar.nl";
            SMTP_PORT = 2525;
            SMTP_SECURITY = "off";
            SMTP_FROM = "vaultwarden@lvdar.nl";
            SMTP_FROM_NAME = "Vaultwarden";
          };
        };
      };
    };
  };
}
