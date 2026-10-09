# services.attic — a binary cache the whole fleet pulls from.
#
# Mesh-only: Nix clients cannot complete gaia's browser OIDC redirect.
#
#   * `services.atticd`'s DynamicUser+StateDirectory hits the /var/lib/private
#     EBUSY trap (as ntfy/gatus did); forced to a static user.
#   * Cache contents on /tank are deliberately NOT in impermanence.persist —
#     an entry would bind-mount /persist over it onto the system SSD. The
#     sqlite index does get a persist entry.
{
  den,
  inputs,
  ...
}: {
  # Inert until `publicKey` is set: the keypair is minted at runtime when the
  # cache is created (`atticd-atticadm`), then pasted into the default below.
  den.aspects.services.attic.client = {
    includes = [den.aspects.core.sops];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkEnableOption;
      inherit (lib.types) nullOr str;

      cfg = config.cosmos.services.attic.client;

      # attic's CLI has no --config; it only reads $XDG_CONFIG_HOME/attic/config.toml.
      configHome = "/run/attic-client";
    in {
      options.cosmos.services.attic.client = {
        serverUrl = mkOption {
          type = str;
          example = "http://cache.example.org:8090";
          description = ''
            The attic server, without a cache name.

            A literal rather than a reference to the server aspect's options:
            den cannot read another host's config, which is the same reason
            gaia.nix hardcodes endeavour's service ports.
          '';
        };

        cacheName = mkOption {
          type = str;
          default = "lvdar";
          description = "The cache on that server. Must match the server aspect's own cacheName.";
        };

        endpoint = mkOption {
          type = str;
          default = "${cfg.serverUrl}/${cfg.cacheName}";
          defaultText = "\${serverUrl}/\${cacheName}";
          description = ''
            The cache to pull from, as a mesh URL. This is the substituter;
            watch-store below wants serverUrl instead, because the CLI takes
            the cache as an argument rather than in the URL.
          '';
        };

        publicKey = mkOption {
          type = nullOr str;
          default = "lvdar:BgBRpHKR8srVXZHj5NRzLcDR6szD6SCpMPC9gTZE7LU=";
          example = "lvdar:abc123...=";
          description = ''
            The cache's signing public key. With this null, no substituter is
            configured at all — Nix refuses paths it cannot verify, so a
            substituter without its key is worse than none.

            Minted by attic when the cache was created and safe to keep in the
            repo: it verifies signatures, it does not make them. The private
            half never leaves keys/attic/token-secret.

            The cache is also marked `public`, which here means "no token needed
            to pull" rather than "reachable by anyone" — it only listens on the
            mesh. That is the same trust boundary loki, prometheus and
            node-exporter already sit behind on this host, and it is what lets
            every peer substitute without a netrc file to distribute and rotate.
          '';
        };

        watchStore.enable = mkEnableOption ''
          uploading every new store path to the cache.

          The half that was missing. Reads were configured on every host from
          the start and writes were configured nowhere, so the cache answered
          404 for every closure this fleet has ever built — CI read it,
          got nothing, and compiled from source. `attic watch-store` closes
          that by tailing the store and pushing what appears.

          On the two hosts that actually build: voyager, which makes the
          expensive closures and emulates pioneer's aarch64 one, and endeavour,
          which runs the nightly lock bump for all three x86_64 systems.

          Paths already on cache.nixos.org are skipped by attic's upstream
          filter, so what lands here is what upstream does not have — overlays,
          this repo's own packages, the emulated aarch64 build. That is also
          the answer to "does this upload my whole store": no, only the part no
          public cache can serve
        '';
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.publicKey != null) {
          nix.settings = {
            # Precedence comes from the server-side cache priority
            # (`attic cache configure lvdar --priority 39`, below upstream's
            # 40): attic is a LAN hop, cache.nixos.org an internet one.
            substituters = [cfg.endpoint];
            trusted-public-keys = [cfg.publicKey];

            # Mesh-only cache; voyager is often off-mesh.
            connect-timeout = 5;
            fallback = true;
          };
        })

        (lib.mkIf cfg.watchStore.enable {
          sops = {
            secrets."keys/attic/push-token" = {
              sopsFile = builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";
              mode = "0400";
            };

            # The CLI reads endpoint and token only from config.toml.
            templates."attic-client.toml".content = ''
              default-server = "${cfg.cacheName}"

              [servers.${cfg.cacheName}]
              endpoint = "${cfg.serverUrl}/"
              token = "${config.sops.placeholder."keys/attic/push-token"}"
            '';
          };

          # For seeding: watch-store only uploads paths that appear after it starts.
          environment.systemPackages = [pkgs.attic-client];

          systemd.tmpfiles.rules = [
            "d ${configHome} 0700 root root - -"
            "d ${configHome}/attic 0700 root root - -"
            "L+ ${configHome}/attic/config.toml - - - - ${config.sops.templates."attic-client.toml".path}"
          ];

          systemd.services.attic-watch-store = {
            description = "Upload new store paths to the attic cache";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target" "netbird.service"];
            wants = ["network-online.target"];

            environment.XDG_CONFIG_HOME = configHome;

            serviceConfig = {
              ExecStart = "${lib.getExe pkgs.attic-client} watch-store ${cfg.cacheName}";

              # Failing off-mesh is normal; keep it off the OnFailure ntfy route.
              Restart = "always";
              RestartSec = 30;

              Nice = 15;
              IOSchedulingClass = "idle";
            };
          };
        })
      ];
    };
  };

  den.aspects.services.attic = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str path;

      cfg = config.cosmos.services.attic;
      dnsDomain = config.cosmos.services.netbird.dnsDomain;

      user = "atticd";
    in {
      options.cosmos.services.attic = {
        port = mkOption {
          type = port;
          default = 8090;
          description = ''
            Free on this host. Not 8080 or 8443, which the netbird proxy and
            kanidm hold, and clear of the 9091-9304 block opencloud sprawls
            across — the range that already forced node_exporter off its
            conventional 9100.
          '';
        };

        dataDir = mkOption {
          type = path;
          example = "/srv/atticd";
          description = ''
            NAR storage, on the array. See the header for why it is not
            persisted.

            This is the one thing here that grows without a bound anyone chose:
            it holds every path every host has ever pushed, until garbage
            collection expires it. That is the whole argument for /tank over
            the SSD.
          '';
        };

        cacheName = mkOption {
          type = str;
          default = "lvdar";
          description = "The cache clients pull from, as <endpoint>/<name>.";
        };

        retention = mkOption {
          type = str;
          default = "3 months";
          description = ''
            How long an unreferenced path survives, as attic's
            `default-retention-period`.

            Matched roughly to core/nix.nix's 30-day GC horizon plus slack: a
            cache that expires paths sooner than clients stop asking for them
            is a cache that misses, and the array has room.
          '';
        };
      };

      config = {
        # EnvironmentFile is opened by systemd as root, so no owner needed.
        sops = {
          secrets."keys/attic/token-secret" = {};
          templates."attic.env".content = ''
            ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder."keys/attic/token-secret"}
          '';
        };

        users = {
          users.${user} = {
            isSystemUser = true;
            group = user;
            home = "/var/lib/atticd";
          };
          groups.${user} = {};
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0750 ${user} ${user} - -"
        ];

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/atticd";
            inherit user;
            group = user;
            mode = "0750";
          }
        ];

        services.atticd = {
          enable = true;
          inherit user;
          group = user;
          environmentFile = config.sops.templates."attic.env".path;

          settings = {
            # Mesh address is assigned at enrollment, unknown at eval time.
            listen = "[::]:${toString cfg.port}";

            # Client-facing URLs are built from this; must be the mesh name.
            api-endpoint = "http://${config.networking.hostName}.${dnsDomain}:${toString cfg.port}/";

            database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";

            storage = {
              type = "local";
              path = cfg.dataDir;
            };

            # Sizes are 16x upstream's: every chunk costs a DB transaction and
            # a sync write, and /tank (raidz1 HDDs, no SLOG) managed ~2.3
            # chunks/s — a 2 GB closure took four hours. Most paths now skip
            # chunking via nar-size-threshold; cross-host closure reuse is
            # where the dedup wins are anyway.
            chunking = {
              nar-size-threshold = 33554432; # 32 MiB
              min-size = 262144; # 256 KiB
              avg-size = 1048576; # 1 MiB
              max-size = 4194304; # 4 MiB
            };

            compression.type = "zstd";

            garbage-collection = {
              interval = "12 hours";
              default-retention-period = cfg.retention;
            };
          };
        };

        # Nested inside serviceConfig on purpose: a top-level mkForce recurses
        # infinitely in den alongside facter (see hosts/pioneer.nix).
        systemd.services.atticd.serviceConfig = {
          DynamicUser = lib.mkForce false;

          # PrivateUsers hides the static UID from the files it owns on /tank.
          PrivateUsers = lib.mkForce false;

          # dataDir must be its own dataset (hosts/_hw/endeavour/disko.nix);
          # unmounted, atticd would silently write to the pool root with the
          # wrong recordsize/sync settings.
          ExecStartPre = [
            (lib.getExe (pkgs.writeShellApplication {
              name = "atticd-datadir-guard";
              runtimeInputs = [pkgs.util-linux];
              text = ''
                if ! mountpoint -q ${lib.escapeShellArg cfg.dataDir}; then
                  echo "${cfg.dataDir} is not a mount point — refusing to start." >&2
                  echo "Chunks would land on the pool root with the wrong" >&2
                  echo "recordsize and sync settings. Create it with:" >&2
                  echo "  zfs create -o recordsize=1M -o sync=disabled tank/atticd" >&2
                  exit 1
                fi
              '';
            }))
          ];
        };

        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
