# services.kavita — reading server for the ebook/light-novel library.
#
# The counterpart to suwayomi rather than a replacement for it: suwayomi
# fetches manga from sources and stores CBZ, while this only ever reads what
# is already on disk. Kavita has no acquisition layer at all — no sources, no
# extensions, nothing to point at a remote site — so filling the library is
# always a separate job from serving it. Readarr would have been that job and
# is retired (archived 2025-06-27, its metadata backend gone), so for now the
# directory is filled by hand.
#
# Two things about the upstream module are worth knowing before changing
# anything here:
#
#   * it rewrites config/appsettings.json from the Nix store on *every* start.
#     Kavita's own UI writes OIDC settings into that same file, so anything
#     configured through the web interface that lands there is silently lost at
#     the next restart. That is why Authority/ClientId/Secret are set below
#     rather than in the UI — they are the three that live in appsettings.json.
#     The behavioural OIDC toggles (auto-provision, role sync) live in Kavita's
#     database instead and are safe to set in the UI.
#
#   * it substitutes only the TokenKey into that file, via replace-secret. The
#     client secret needs the same treatment, so this appends a second
#     replace-secret pass and a second credential rather than putting the
#     secret in the store.
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
            # `Port`, capitalised: settings is a freeform submodule, so a
            # lowercase `port` is accepted silently, written to
            # appsettings.json, ignored by Kavita, and leaves the real option
            # sitting at its default.
            Port = cfg.port;

            # Bound to everything by the upstream default, which is what
            # edge termination needs: netbird-proxy dials `endeavour:5000`
            # over the mesh, and a loopback socket refuses that. Reach is
            # governed by the firewall, which opens this on wt0 only.
            OpenIdConnectSettings = {
              # kanidm publishes discovery at
              # <authority>/.well-known/openid-configuration, which is what
              # Kavita fetches to learn the rest of the endpoints.
              Authority = "https://auth.lvdar.nl/oauth2/openid/kavita";
              ClientId = "kavita";
              Secret = "@OIDC_SECRET@";
            };
          };
          tokenKeyFile = config.sops.secrets."keys/kavita/token".path;
        };

        # Read access to the library. Not the primary group — unlike the arrs,
        # this service never creates a file anyone else has to read, so it has
        # no reason to own anything under mediaDir.
        users.users.kavita.extraGroups = ["media"];

        systemd.tmpfiles.rules = [
          "d '${cfg.libraryDir}' 0775 root media - -"
        ];

        systemd.services.kavita = {
          serviceConfig.LoadCredential = [
            "oidc-secret:${config.sops.secrets."keys/kavita/oauth-client-secret".path}"
          ];

          # mkAfter so this lands behind the upstream preStart, which installs
          # appsettings.json in the first place — there is nothing to
          # substitute into before it has run.
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

          systems.oauth2.kavita = {
            displayName = "Kavita";
            basicSecretFile = config.sops.secrets."keys/kavita/oauth-client-secret".path;

            # Both legs of the ASP.NET Core OIDC handler. The sign-out callback
            # is not optional decoration: without it registered, logging out
            # lands on a kanidm error rather than back on Kavita.
            originUrl = [
              "https://${cfg.domain}/signin-oidc"
              "https://${cfg.domain}/signout-callback-oidc"
            ];
            originLanding = "https://${cfg.domain}";
            scopeMaps.kavita-users = ["openid" "profile" "email"];

            # Deliberately NOT allowInsecureClientDisablePkce, unlike jellyfin,
            # traccar and open-webui. Those needed the concession because their
            # clients send no code challenge; ASP.NET Core's handler enables
            # PKCE by default on the authorization code flow, so kanidm's
            # requirement should be met as-is. If the token exchange fails with
            # an opaque invalid_request on first login, this is the knob — but
            # confirm the challenge is really absent before reaching for it.
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
