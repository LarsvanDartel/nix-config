# services.tino — TINO (github:confirm/tino), a git+Typst-backed
# collaborative document editor. See pkgs/tino.nix for why it is packaged
# natively. Integrated with kanidm like immich/grafana/opencloud: a
# confidential OAuth2 client in services/kanidm.nix, published ungated
# through gaia's netbird-proxy because TINO does its own OIDC login.
{den, ...}: {
  den.aspects.services.tino = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str enum;

      cfg = config.cosmos.services.tino;
      user = "tino";

      pythonEnv = pkgs.python3.withPackages (ps: [ps.tino]);

      # Upstream's Dockerfile does `git lfs install --system`; there is no
      # writable system gitconfig in the store, so it is handed to git via
      # GIT_CONFIG_SYSTEM (git 2.32+ reads that in place of the compiled-in
      # path), with core.attributesFile pointing at the repo's gitattributes.
      gitConfig = pkgs.writeText "tino-gitconfig" ''
        [core]
            attributesFile = ${pkgs.python3Packages.tino}/share/tino/gitattributes
        [filter "lfs"]
            clean = git-lfs clean -- %f
            smudge = git-lfs smudge -- %f
            process = git-lfs filter-process
            required = true
      '';

      server = pkgs.writeShellApplication {
        name = "tino-server";
        runtimeInputs = [pythonEnv pkgs.gitMinimal pkgs.git-lfs pkgs.typst];
        text = ''
          export TINO_OIDC_CLIENT_SECRET TINO_SECRET_KEY
          TINO_OIDC_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/oidc-client-secret")"
          TINO_SECRET_KEY="$(cat "$CREDENTIALS_DIRECTORY/session-secret-key")"
          exec gunicorn \
            -k uvicorn.workers.UvicornWorker \
            -w 1 \
            -b 0.0.0.0:${toString cfg.port} \
            --worker-tmp-dir /tmp \
            --chdir /tmp \
            "tino:create_app()"
        '';
      };
    in {
      options.cosmos.services.tino = {
        port = mkOption {
          type = port;
          default = 3040;
          description = ''
            Loopback/mesh port. Not 3030 (typstnique) or 3031 (site) — see
            hosts/endeavour.nix's port list for what else is taken nearby.
          '';
        };

        domain = mkOption {
          type = str;
          default = "tino.lvdar.nl";
          description = "Public name, which must match the published service and the kanidm OAuth2 client's originUrl.";
        };

        accentColour = mkOption {
          type = enum [
            "grey"
            "cold-grey"
            "warm-grey"
            "red"
            "orange"
            "yellow"
            "olive"
            "lime"
            "green"
            "sea-green"
            "blue"
            "azure"
            "violet"
            "purple"
            "fuchsia"
            "rose"
          ];
          default = "orange";
          description = ''
            TINO_ACCENT_COLOUR — the UI accent colour family (login button,
            highlights). Must match a family from the confirm design
            colours TINO's own vendored colours.css defines (see
            pkgs/tino.nix). "red" is GEWIS's brand colour.
          '';
        };
      };

      config = {
        users.users.${user} = {
          isSystemUser = true;
          group = user;
          home = "/var/lib/tino";
        };
        users.groups.${user} = {};

        systemd.tmpfiles.rules = [
          "d /var/lib/tino 0750 ${user} ${user} - -"
          # TINO reads no ambient font env var: it builds its own
          # `typst --font-path` from TINO_FONT_DIR (config.py), a writable
          # subdir of TINO_DATA_DIR backing a FontService (per-instance font
          # upload in the UI). So the fix is seeding that directory with `C` —
          # copy once if absent — so a font uploaded later is never clobbered
          # by activation. Lato Black is the GEWIS letterhead wordmark,
          # embedded in the corporate PDFs, not a system font typst would
          # discover on its own.
          "C /var/lib/tino/fonts/lato - ${user} ${user} - ${pkgs.lato}/share/fonts"
        ];
        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/tino";
            inherit user;
            group = user;
            mode = "0750";
          }
        ];

        # Owned by kanidm, not tino: services/kanidm.nix's provisioning reads
        # the same file as `basicSecretFile` so both sides of the client agree
        # on the secret. tino still reaches it via LoadCredential, which
        # systemd loads as root before ownership would apply.
        sops.secrets."keys/tino/oidc-client-secret".owner = "kanidm";

        # Left unset, TINO generates a random session-signing key on every
        # process start, and a gunicorn respawning the worker (worker timeout
        # on a slow OIDC call, a crash, a deploy) silently invalidates every
        # session cookie mid-flight — "log in successfully, land back on the
        # login page": the callback and the next request hit different
        # secrets. A stable key removes the respawn as a variable.
        sops.secrets."keys/tino/session-secret-key".owner = user;

        systemd.services.tino = {
          description = "TINO — collaborative Typst editor";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];

          environment = {
            TINO_DATA_DIR = "/var/lib/tino";
            TINO_BASE_URL = "https://${cfg.domain}";
            TINO_OIDC_DISCOVERY_URL = "https://auth.lvdar.nl/oauth2/openid/tino/.well-known/openid-configuration";
            TINO_OIDC_CLIENT_ID = "tino";
            # kanidm's raw "groups" claim is the identity's entire fleet-wide
            # membership (see services/kanidm.nix); TINO stores the whole
            # userinfo response in its session cookie, and the pushed
            # Set-Cookie blew past the ~4KB cap browsers silently enforce —
            # login completed server-side and never stuck client-side.
            # tino_groups is the small mapped claim instead.
            TINO_OIDC_GROUPS_CLAIM = "tino_groups";
            TINO_ACCENT_COLOUR = cfg.accentColour;
            GIT_CONFIG_SYSTEM = toString gitConfig;
            XDG_CACHE_HOME = "/var/lib/tino/.cache";
          };

          serviceConfig = {
            User = user;
            Group = user;
            WorkingDirectory = "/tmp";
            LoadCredential = [
              "oidc-client-secret:${config.sops.secrets."keys/tino/oidc-client-secret".path}"
              "session-secret-key:${config.sops.secrets."keys/tino/session-secret-key".path}"
            ];
            ExecStart = lib.getExe server;
            Restart = "on-failure";
            RestartSec = 10;
          };
        };

        # netbird-proxy dials over the mesh, so the port opens on wt0 only —
        # endeavour is edgeTerminated.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
