# services.kavita — reading server for the ebook/light-novel library.
#
# Module traps:
#   * appsettings.json is rewritten from the store on every start, so OIDC
#     Authority/ClientId/Secret live here. The behavioural OIDC toggles live in
#     kavita.db ServerSetting row 40 and *that copy wins*: fields below are
#     first-run seeds. Never toggle them in the UI — "disable password auth"
#     once locked the only account out; recovery was a sqlite UPDATE on row
#     40 with the service stopped.
#   * the module substitutes only TokenKey; hence the replace-secret pass below.
{den, ...}: {
  den.aspects.services.kavita = {
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
            # `Port`, capitalised: lowercase is accepted by the freeform
            # submodule and silently ignored by Kavita.
            Port = cfg.port;

            OpenIdConnectSettings = {
              Authority = "https://auth.lvdar.nl/oauth2/openid/kavita";
              ClientId = "kavita";
              Secret = "@OIDC_SECRET@";

              # Kavita's default is .NET's schema URI, which kanidm cannot emit.
              RolesClaim = "kavita_roles";

              # Without at least Login, a provisioned user is refused with
              # "You do not have the required roles".
              DefaultRoles = ["Login"];
              ProvisionAccounts = true;

              # Seed only (see header). kanidm runs on this host, so OIDC-only
              # is unreachable exactly when kanidm is.
              DisablePasswordAuthentication = false;
            };
          };
          tokenKeyFile = config.sops.secrets."keys/kavita/token".path;
        };

        users.users.kavita.extraGroups = ["media"];

        systemd.tmpfiles.rules = [
          "d '${cfg.libraryDir}' 0775 root media - -"
        ];

        systemd.services.kavita = {
          serviceConfig.LoadCredential = [
            "oidc-secret:${config.sops.secrets."keys/kavita/oauth-client-secret".path}"
          ];

          preStart = mkAfter ''
            ${pkgs.replace-secret}/bin/replace-secret '@OIDC_SECRET@' \
              "$CREDENTIALS_DIRECTORY/oidc-secret" \
              '${dataDir}/config/appsettings.json'
          '';
        };

        sops.secrets = {
          # Must be stable: a new value logs everyone out. Generate with
          #   head -c 64 /dev/urandom | base64 --wrap=0
          "keys/kavita/token" = {};

          # kanidm reads it directly; systemd hands Kavita a LoadCredential copy.
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

            # Kavita's exact role names; single-word only.
            supplementaryScopeMaps.kavita-users = ["kavita_roles"];
            claimMaps.kavita_roles = {
              joinType = "array";
              valuesByGroup = {
                kavita-users = ["Login" "Download" "Bookmark"];
                kavita-admins = ["Admin"];
              };
            };

            # Without the sign-out callback, logout lands on a kanidm error.
            originUrl = [
              "https://${cfg.domain}/signin-oidc"
              "https://${cfg.domain}/signout-callback-oidc"
            ];
            originLanding = "https://${cfg.domain}";
            scopeMaps.kavita-users = ["openid" "profile" "email"];

            # Deliberately NOT allowInsecureClientDisablePkce (unlike jellyfin
            # and traccar): ASP.NET Core sends PKCE. If token exchange fails with
            # invalid_request, confirm the challenge is absent before using it.
            preferShortUsername = true;
          };
        };

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
