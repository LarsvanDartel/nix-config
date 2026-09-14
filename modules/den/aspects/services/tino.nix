# services.tino — TINO (github:confirm/tino), a git+Typst-backed
# collaborative document editor. See pkgs/tino.nix for why it is packaged
# natively rather than run from upstream's Docker image.
#
# Integrated with kanidm the same way immich/grafana/opencloud are: a
# confidential OAuth2 client provisioned in services/kanidm.nix, published
# through gaia's netbird-proxy ungated because TINO does its own OIDC login.
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
      inherit (lib.types) port str;

      cfg = config.cosmos.services.tino;
      user = "tino";

      pythonEnv = pkgs.python3.withPackages (ps: [ps.tino]);

      # `git lfs install --system` (what upstream's Dockerfile does) writes
      # the LFS filter into the system gitconfig, and `core.attributesFile`
      # points it at the gitattributes shipped in the repo. There is nowhere
      # writable to put a system gitconfig in the store, so this is handed to
      # git directly via GIT_CONFIG_SYSTEM instead — git 2.32+ reads that
      # env var in place of the compiled-in path.
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
          export TINO_OIDC_CLIENT_SECRET
          TINO_OIDC_CLIENT_SECRET="$(cat "$CREDENTIALS_DIRECTORY/oidc-client-secret")"
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
      };

      config = {
        users.users.${user} = {
          isSystemUser = true;
          group = user;
          home = "/var/lib/tino";
        };
        users.groups.${user} = {};

        systemd.tmpfiles.rules = ["d /var/lib/tino 0750 ${user} ${user} - -"];
        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/tino";
            inherit user;
            group = user;
            mode = "0750";
          }
        ];

        # Owned by kanidm rather than tino: services/kanidm.nix's oauth2
        # provisioning reads the same file as `basicSecretFile` so both sides
        # of the client agree on the secret. tino's own service still reaches
        # it via LoadCredential below, which systemd loads as root before the
        # ownership check would apply.
        sops.secrets."keys/tino/oidc-client-secret".owner = "kanidm";

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
            GIT_CONFIG_SYSTEM = toString gitConfig;
            XDG_CACHE_HOME = "/var/lib/tino/.cache";
          };

          serviceConfig = {
            User = user;
            Group = user;
            WorkingDirectory = "/tmp";
            LoadCredential = "oidc-client-secret:${config.sops.secrets."keys/tino/oidc-client-secret".path}";
            ExecStart = lib.getExe server;
            Restart = "on-failure";
            RestartSec = 10;
          };
        };

        # netbird-proxy reaches it over the mesh like any other target, so the
        # port opens on wt0 and nowhere else — endeavour is edgeTerminated.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
