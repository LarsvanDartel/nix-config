# services.paperless — document archive with OCR, behind kanidm.
#
# Chosen over Papra, which is packaged here too and is the nicer app to look
# at, because OCR and the auto-tagging classifier are the reason to keep a
# document archive at all. Without them everything is filed by hand forever,
# which is the failure mode that gets these abandoned. Papra also has one
# maintainer; paperless-ngx is the community fork that exists because the
# original went unmaintained — the same story as Readarr, with the good ending.
#
# Unlike microbin this needs no forward-auth: paperless speaks OIDC natively
# through django-allauth, so it follows the pattern every other service here
# uses and gaia publishes it directly.
#
# The upstream module brings its own postgres user and redis instance, so
# nothing here touches immich's database beyond sharing the same postgresql
# server — which is what `database.createLocally` does, via a socket and
# ensureDBOwnership.
{den, ...}: {
  den.aspects.services.paperless = {
    # For the `media` group and mediaDir. The base arr aspect is only those two
    # things; this does not pull in the download stack.
    includes = [den.aspects.services.arr];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) bool port str;

      cfg = config.cosmos.services.paperless;
      arr = config.cosmos.services.arr;

      # /accounts/ is where paperless mounts allauth (paperless/urls.py), oidc
      # is allauth's OPENID_CONNECT_URL_PREFIX default, and the trailing
      # segments come from the provider's own urlpatterns. Checked against the
      # vendored allauth rather than assumed: a wrong redirect URI is rejected
      # *after* a successful login, so it reads as a broken IdP rather than a
      # wrong string.
      providerId = "kanidm";
      callback = "https://${cfg.domain}/accounts/oidc/${providerId}/login/callback/";
    in {
      options.cosmos.services.paperless = {
        expose = mkOption {
          type = bool;
          default = false;
        };

        port = mkOption {
          type = port;
          default = 28981;
        };

        domain = mkOption {
          type = str;
          default = "paperless.lvdar.nl";
          description = ''
            Public name. Becomes PAPERLESS_URL, which paperless uses to build
            absolute links and to decide which Host headers it will answer to —
            so an unset value behind a proxy is a DisallowedHost error rather
            than a cosmetic problem.
          '';
        };

        ocrLanguage = mkOption {
          type = str;
          default = "nld+eng";
          description = ''
            Tesseract languages, '+'-separated. Dutch first because most of
            what lands here is; English second so bilingual documents still
            come out. Every language listed costs OCR time on every page.
          '';
        };
      };

      config = {
        services.paperless = {
          enable = true;
          inherit (cfg) port domain;

          # Bound to the mesh, not loopback: endeavour is edge-terminated, so
          # netbird-proxy dials this port over wt0 and a loopback socket would
          # refuse it. Reach is governed by the firewall, which opens this on
          # wt0 only.
          address = "0.0.0.0";

          database.createLocally = true;

          # On the array, beside the other libraries: scanned documents are
          # the archive, and the system disk is the impermanent one.
          mediaDir = "${arr.mediaDir}/library/documents";
          consumptionDir = "${arr.mediaDir}/library/documents-inbox";

          passwordFile = config.sops.secrets."keys/paperless/admin-password".path;

          settings = {
            PAPERLESS_OCR_LANGUAGE = cfg.ocrLanguage;

            # Give the archive a shape on disk rather than a pile of hashes, so
            # the files remain usable if paperless ever is not.
            PAPERLESS_FILENAME_FORMAT = "{created_year}/{correspondent}/{title}";

            PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";

            # Create the local account on first OIDC login instead of making
            # every user exist twice.
            PAPERLESS_SOCIAL_AUTO_SIGNUP = true;

            # PAPERLESS_SOCIALACCOUNT_PROVIDERS is deliberately NOT here: it
            # carries the client secret and settings goes to the store. It
            # arrives through environmentFile below.
          };

          environmentFile = config.sops.templates."paperless.env".path;
        };

        # Regular login stays enabled, unlike immich's passwordLogin.
        #
        # kanidm runs on this host. If it is down or misprovisioned, an
        # OIDC-only paperless is unreachable at exactly the moment someone
        # needs to look something up — and unlike jellyfin there is no second
        # way in. The superuser above is the break-glass account.

        sops.secrets = {
          "keys/paperless/admin-password".owner = "paperless";
          "keys/paperless/oauth-client-secret".owner = "kanidm";
        };

        # json.loads'd straight out of the environment by paperless
        # (settings/__init__.py), so this is allauth's provider dict as-is.
        sops.templates."paperless.env" = {
          content = ''
            PAPERLESS_SOCIALACCOUNT_PROVIDERS=${builtins.toJSON {
              openid_connect = {
                OAUTH_PKCE_ENABLED = true;
                APPS = [
                  {
                    provider_id = providerId;
                    name = "Kanidm";
                    client_id = "paperless";
                    # The placeholder goes through builtins.toJSON intact —
                    # it carries no quotes or backslashes to escape — and
                    # sops-nix substitutes the real value when it renders the
                    # file at activation.
                    secret = config.sops.placeholder."keys/paperless/oauth-client-secret";
                    settings.server_url = "https://auth.lvdar.nl/oauth2/openid/paperless/.well-known/openid-configuration";
                  }
                ];
              };
            }}
          '';
          owner = "paperless";
        };

        users.users.paperless.extraGroups = ["media"];

        # Override the module's own rules rather than shadowing them with a
        # second set. Both create these paths, and systemd-tmpfiles takes the
        # first file it reads and logs "Duplicate line ... ignoring" for the
        # rest — which happened to resolve in our favour, but silently, and
        # only because of how the two filenames sort.
        #
        # `media` and group-write so scans can be dropped into the inbox by
        # something other than paperless itself; the module's default would
        # make both directories paperless:paperless.
        systemd.tmpfiles.settings."10-paperless" = let
          shared = lib.mkForce {
            user = "paperless";
            group = "media";
            mode = "0775";
          };
        in {
          ${config.services.paperless.mediaDir}.d = shared;
          ${config.services.paperless.consumptionDir}.d = shared;
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = config.services.paperless.dataDir;
            user = "paperless";
            group = "paperless";
            mode = "0750";
          }
        ];

        services.kanidm.provision = {
          groups.paperless-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };

          systems.oauth2.paperless = {
            displayName = "Paperless";
            basicSecretFile = config.sops.secrets."keys/paperless/oauth-client-secret".path;
            originUrl = callback;
            originLanding = "https://${cfg.domain}";
            scopeMaps.paperless-users = ["openid" "profile" "email"];

            # allauth sends a code challenge (OAUTH_PKCE_ENABLED above), so
            # kanidm's PKCE requirement is met without the concession jellyfin,
            # traccar and open-webui each had to make.
            preferShortUsername = true;
          };
        };

        services.nginx.virtualHosts = lib.mkIf (cfg.expose && !config.cosmos.networking.edgeTerminated) {
          ${cfg.domain} = {
            forceSSL = true;
            enableACME = false;
            sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
            sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";
            locations."/".proxyPass = "http://127.0.0.1:${toString cfg.port}";
          };
        };
      };
    };
  };
}
