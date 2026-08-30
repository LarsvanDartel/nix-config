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
        # Note, if you reach for it: `paperless-manage` is broken as nixpkgs
        # ships it here. The wrapper composes
        #
        #   sudo -u paperless -g paperless  -g redis-paperless -E
        #
        # and sudo accepts only one -g, so it exits with its own usage message
        # before running anything. Working around it means invoking the command
        # as the paperless user so the wrapper takes its `sudo=exec` branch.
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

          settings =
            {
              PAPERLESS_OCR_LANGUAGE = cfg.ocrLanguage;

              # Give the archive a shape on disk rather than a pile of hashes, so
              # the files remain usable if paperless ever is not.
              PAPERLESS_FILENAME_FORMAT = "{created_year}/{correspondent}/{title}";

              PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";

              # Create the local account on first OIDC login instead of making
              # every user exist twice.
              PAPERLESS_SOCIAL_AUTO_SIGNUP = true;

              # ...and give it permissions, which auto-signup does not. Without
              # this a new account is created with none at all and every request
              # it makes is refused — including /api/ui_settings/, so the SPA
              # fails to load and shows a bare 403 rather than anything about
              # permissions. That is what the first OIDC login did on
              # 2026-08-30.
              #
              # The SOCIAL_ one, not PAPERLESS_ACCOUNT_DEFAULT_GROUPS: that is
              # the local-signup path, which is unused here. Comma-separated if
              # more are ever wanted.
              #
              # "Users" is a Django group, so it lives in paperless's database
              # rather than here — like the libraries in kavita and the
              # superuser flag. It carries full rights over documents, notes,
              # tags, correspondents, document types, storage paths, saved
              # views, custom fields, share links, UI settings and one's own
              # MFA, plus read-only visibility of the task queue. It withholds
              # what administers the server rather than uses it: workflows,
              # application configuration, the mail accounts (which hold
              # credentials), and the guardian/session/socialaccount internals.
              PAPERLESS_SOCIAL_ACCOUNT_DEFAULT_GROUPS = "Users";
            }
            // lib.optionalAttrs cfg.ai.enable {
              # Suggestions only — a title, tags, correspondents, a document
              # type, storage paths and up to three dates, which paperless then
              # matches by name against objects that already exist. They are
              # offered on the document view and cached, NOT applied during
              # consumption, so a slow model costs a wait when opening a
              # document rather than a stalled ingest queue.
              #
              # Distinct from the scikit-learn classifier, which is already on
              # and needs nothing: that one learns from corrections and can only
              # propose tags you already have. This one reads the document and
              # can propose a title and a date, which the classifier cannot.
              PAPERLESS_AI_ENABLED = true;
              PAPERLESS_AI_LLM_BACKEND = "ollama";
              PAPERLESS_AI_LLM_ENDPOINT = cfg.ai.endpoint;
              PAPERLESS_AI_LLM_MODEL = cfg.ai.model;

              # PAPERLESS_AI_LLM_OUTPUT_LANGUAGE is deliberately unset. It adds
              # a second pass that translates the suggestions, and matching is
              # by name — so forcing a language is a way to stop suggested tags
              # from matching the tags that exist.
              #
              # Embeddings are likewise unset: they power the chat-over-
              # documents feature, not these suggestions, and would mean pulling
              # another model for something nobody has asked for yet.

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
        #
        # Single-quoted, which systemd strips when it reads an EnvironmentFile
        # and which the shell needs. The service works either way — systemd
        # takes the value literally — but `paperless-manage` *sources* this
        # same file, and an unquoted JSON object comes apart in the shell:
        #
        #   json.decoder.JSONDecodeError: Expecting property name enclosed in
        #   double quotes: line 1 column 2 (char 1)
        #
        # which makes every management command unusable while OIDC is
        # configured. The JSON contains double quotes and no single ones, so
        # wrapping it this way is safe.
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
