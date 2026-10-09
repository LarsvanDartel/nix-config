# services.paperless — document archive with OCR, behind kanidm.
{den, ...}: {
  den.aspects.services.paperless = {
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

      # Wrong redirect URI is rejected *after* a successful login.
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

        ai = {
          enable = mkOption {
            type = bool;
            default = false;
            description = ''
              Offer LLM-generated suggestions when a document is opened.

              Off by default because it needs a model to talk to, which is a
              fact about the host rather than about paperless.
            '';
          };

          endpoint = mkOption {
            type = str;
            default = "http://127.0.0.1:11434";
            description = ''
              Where the model lives. Loopback works because paperless-web —
              the only unit that makes this call — runs with
              PrivateNetwork=no. The consumer and scheduler are in their own
              network namespace, where this address would mean something else
              entirely and reach nothing.
            '';
          };

          model = mkOption {
            type = str;
            default = "qwen3:14b";
            description = ''
              A starting point, not a recommendation for every host — what is
              actually available is a property of that host's ollama.

              If suggestions come back malformed, this model's thinking mode
              leaking into the structured output is the first thing to
              suspect; a plainer instruct model is a one-word change.
            '';
          };
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
        # `paperless-manage` is broken (wrapper passes sudo two -g flags);
        # run it as the paperless user so it takes the `sudo=exec` branch.
        services.paperless = {
          enable = true;
          inherit (cfg) port domain;

          # Edge-terminated: netbird-proxy dials over wt0.
          address = "0.0.0.0";

          database.createLocally = true;

          mediaDir = "${arr.mediaDir}/library/documents";
          consumptionDir = "${arr.mediaDir}/library/documents-inbox";

          passwordFile = config.sops.secrets."keys/paperless/admin-password".path;

          settings =
            {
              PAPERLESS_OCR_LANGUAGE = cfg.ocrLanguage;

              PAPERLESS_FILENAME_FORMAT = "{created_year}/{correspondent}/{title}";

              PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";

              PAPERLESS_SOCIAL_AUTO_SIGNUP = true;

              # Auto-signup grants no permissions; without this the first
              # OIDC login got a bare 403 (2026-08-30).
              PAPERLESS_SOCIAL_ACCOUNT_DEFAULT_GROUPS = "Users";
            }
            // lib.optionalAttrs cfg.ai.enable {
              # Suggestions on document view only, not applied during consumption.
              PAPERLESS_AI_ENABLED = true;
              PAPERLESS_AI_LLM_BACKEND = "ollama";
              PAPERLESS_AI_LLM_ENDPOINT = cfg.ai.endpoint;
              PAPERLESS_AI_LLM_MODEL = cfg.ai.model;

              # OUTPUT_LANGUAGE unset: translation breaks name-matching of tags.
              # SOCIALACCOUNT_PROVIDERS carries a secret: via environmentFile.
            };

          environmentFile = config.sops.templates."paperless.env".path;
        };

        # Password login stays enabled as break-glass for when kanidm is down.

        sops.secrets = {
          "keys/paperless/admin-password".owner = "paperless";
          "keys/paperless/oauth-client-secret".owner = "kanidm";
        };

        # Single-quoted: `paperless-manage` sources this file and unquoted JSON
        # breaks in the shell.
        sops.templates."paperless.env" = {
          content = ''
            PAPERLESS_SOCIALACCOUNT_PROVIDERS='${builtins.toJSON {
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
            }}'
          '';
          owner = "paperless";
        };

        users.users.paperless.extraGroups = ["media"];

        # mkForce over the module's rules: duplicate tmpfiles lines are ignored
        # by sort order, not merged.
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
