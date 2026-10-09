# services.tino — TINO (github:confirm/tino), a git+Typst-backed
# collaborative document editor. Published ungated: TINO does its own OIDC.
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

      # Replaces upstream's `git lfs install --system`: the store has no
      # writable system gitconfig, so it goes in via GIT_CONFIG_SYSTEM.
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
          # TINO only reads fonts from TINO_FONT_DIR (user-uploadable), so seed
          # it with `C` (copy once if absent). Lato Black is the GEWIS wordmark.
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

        # Owned by kanidm: its provisioning reads the same file as
        # `basicSecretFile`. tino gets it via LoadCredential.
        sops.secrets."keys/tino/oidc-client-secret".owner = "kanidm";

        # Unset, TINO picks a random key per process, so every gunicorn worker
        # respawn silently invalidates all sessions (login loops).
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
            # Not "groups": that claim is fleet-wide and pushed the session
            # cookie past the ~4KB browser cap, so logins never stuck.
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

        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
