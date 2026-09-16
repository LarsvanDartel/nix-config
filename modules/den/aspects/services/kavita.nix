# services.kavita — reading server for the ebook/light-novel library.
#
# Reads what is already on disk: Kavita has no acquisition layer (suwayomi
# is the counterpart that fetches; readarr is retired, archived 2025-06-27),
# so the library is filled by hand for now.
#
# Two module traps:
#
#   * config/appsettings.json is rewritten from the Nix store on *every*
#     start, so anything clicked in the UI that lands in that file is lost.
#     Authority/ClientId/Secret are therefore set here, not in the UI. The
#     behavioural OIDC toggles are a second copy, one JSON blob in
#     ServerSetting row 40 of kavita.db, and *that copy wins* (measured
#     2026-08-30): every other OIDC field below is a first-run seed, not a
#     setting, and saving the OIDC form in the UI rewrites the whole blob.
#     The UI is the dangerous place to change them — "disable password
#     authentication" clicked there once locked the only account out
#     (provisioned identity with no roles, local login gone); recovery was a
#     sqlite UPDATE against row 40 with the service stopped.
#   * the module substitutes only the TokenKey; the client secret needs the
#     same treatment, hence the second replace-secret pass below rather than
#     a secret in the store.
{den, ...}: {
  den.aspects.services.kavita = {
    # For the `media` group and mediaDir. The base arr aspect is just those
    # two things — this does not pull in the download stack.
    includes = [den.aspects.services.arr];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) bool path port str;
      inherit (lib.modules) mkAfter mkIf;

      cfg = config.cosmos.services.kavita;
      arr = config.cosmos.services.arr;

      dataDir = config.services.kavita.dataDir;
    in {
      options.cosmos.services.kavita = {
        expose = mkOption {
          type = bool;
          default = false;
        };

        port = mkOption {
          type = port;
          default = 5000;
        };

        domain = mkOption {
          type = str;
          default = "kavita.lvdar.nl";
          description = ''
            Public name. Used for the OIDC redirect URIs, which must match what
            kanidm has registered exactly — a mismatch is rejected at the
            callback, after a successful login, and reads like a broken IdP
            rather than a wrong URL.
          '';
        };

        libraryDir = mkOption {
          type = path;
          default = "${arr.mediaDir}/library/books";
          defaultText = "a `books` directory beside the arr libraries";
          description = ''
            Where the books live.

            Kavita does not read this: library paths are held in its own
            database and added through its UI. Declaring it here is what
            creates the directory with the right group, so that the entry
            added in the UI has somewhere to point.
          '';
        };
      };

      config = {
        services.kavita = {
          enable = true;
          settings = {
            # `Port`, capitalised: settings is a freeform submodule, so
            # lowercase `port` is accepted silently, written to the file, and
            # ignored by Kavita.
            Port = cfg.port;

            # Bound to everything by the upstream default — what edge
            # termination needs: netbird-proxy dials `endeavour:5000` over
            # the mesh and a loopback socket refuses. Reach is governed by
            # the firewall, which opens this on wt0 only.
            OpenIdConnectSettings = {
              Authority = "https://auth.lvdar.nl/oauth2/openid/kavita";
              ClientId = "kavita";
              Secret = "@OIDC_SECRET@";

              # Kavita's default is .NET's schema URI, which kanidm cannot
              # produce (its claim names are bare identifiers) — met in the
              # middle on a name both can express. The claim kanidm is told
              # to emit below.
              RolesClaim = "kavita_roles";

              # A floor, not the policy: what a provisioned account gets if
              # it arrives without a claim. Without at least Login, a new
              # user is created and then refused with "You do not have the
              # required roles" — a lockout that looks like a bug.
              DefaultRoles = ["Login"];
              ProvisionAccounts = true;

              # Seed for a fresh install only — the database overrides it
              # once it exists (see the header). Same call as paperless:
              # kanidm runs on this host, so OIDC-only is unreachable
              # exactly when kanidm is.
              DisablePasswordAuthentication = false;
            };
          };
          tokenKeyFile = config.sops.secrets."keys/kavita/token".path;
        };

        # Read access only. Unlike the arrs, this service never creates a
        # file anyone else has to read, so it has no reason to own anything
        # under mediaDir.
        users.users.kavita.extraGroups = ["media"];

        systemd.tmpfiles.rules = [
          "d '${cfg.libraryDir}' 0775 root media - -"
        ];

        systemd.services.kavita = {
          serviceConfig.LoadCredential = [
            "oidc-secret:${config.sops.secrets."keys/kavita/oauth-client-secret".path}"
          ];

          # mkAfter so this lands behind the upstream preStart that installs
          # appsettings.json — nothing to substitute into before it has run.
          preStart = mkAfter ''
            ${pkgs.replace-secret}/bin/replace-secret '@OIDC_SECRET@' \
              "$CREDENTIALS_DIRECTORY/oidc-secret" \
              '${dataDir}/config/appsettings.json'
          '';
        };

        sops.secrets = {
          # Signs Kavita's session JWTs, so it has to be stable: a new value
          # logs everyone out. 512+ bits, generated with
          #   head -c 64 /dev/urandom | base64 --wrap=0
          "keys/kavita/token" = {};

          # One secret, two readers. kanidm reads it as basicSecretFile;
          # systemd reads it as root and hands Kavita a private copy, so the
          # owner here is kanidm and Kavita never needs access to the file.
          "keys/kavita/oauth-client-secret".owner = "kanidm";
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = dataDir;
            user = "kavita";
            group = "kavita";
            mode = "0750";
          }
        ];

        services.kanidm.provision = {
          groups.kavita-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };

          groups.kavita-admins = {
            overwriteMembers = false;
            members = ["lvdar"];
          };

          systems.oauth2.kavita = {
            displayName = "Kavita";
            basicSecretFile = config.sops.secrets."keys/kavita/oauth-client-secret".path;

            # Kavita matches these against its own role names exactly —
            # Kavita's spelling, not ours. Only single-word roles: a claim
            # value with a space in it is not worth the risk for permissions
            # an SSO user does not need.
            supplementaryScopeMaps.kavita-users = ["kavita_roles"];
            claimMaps.kavita_roles = {
              joinType = "array";
              valuesByGroup = {
                kavita-users = ["Login" "Download" "Bookmark"];
                kavita-admins = ["Admin"];
              };
            };

            # Both legs of the OIDC handler — without the sign-out callback
            # registered, logging out lands on a kanidm error rather than
            # back on Kavita.
            originUrl = [
              "https://${cfg.domain}/signin-oidc"
              "https://${cfg.domain}/signout-callback-oidc"
            ];
            originLanding = "https://${cfg.domain}";
            scopeMaps.kavita-users = ["openid" "profile" "email"];

            # Deliberately NOT allowInsecureClientDisablePkce, unlike
            # jellyfin and traccar (their clients send no code challenge):
            # ASP.NET Core's handler enables PKCE by default on the auth-code
            # flow. If the token exchange fails with an opaque invalid_request
            # on first login, this is the knob — confirm the challenge is
            # really absent before reaching for it.
            preferShortUsername = true;
          };
        };

        # Dropped when the edge terminates TLS: netbird-proxy forwards straight
        # to cfg.port over the mesh, so there is nothing for a local vhost to do.
        services.nginx.virtualHosts = mkIf (cfg.expose && !config.cosmos.networking.edgeTerminated) {
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
