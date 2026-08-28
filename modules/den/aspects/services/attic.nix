# services.attic — a binary cache the whole fleet pulls from.
#
# Four hosts currently build everything independently, and one of them builds
# for another: pioneer is aarch64 and is assembled on voyager under binfmt
# emulation, because a Pi 3 with 866 MiB cannot build its own closure. Every
# `nix run .#pioneer` therefore re-emulates whatever cache.nixos.org does not
# already have, from scratch, on a laptop. This makes that happen once.
#
# On endeavour because it is the host with the array and the uptime, and
# mesh-only because a binary cache is a machine-to-machine protocol: a Nix
# client cannot complete the browser OIDC redirect that gaia's gate answers
# with, so publishing it would mean turning bearerAuth off and leaning on
# attic's own tokens as the only lock. There is no reason to take that trade
# when every host that wants the cache is already on the mesh.
#
# Two nixpkgs-module traps are worked around here, both previously documented
# elsewhere in this repo:
#
#   * `services.atticd` sets DynamicUser = true AND StateDirectory = "atticd",
#     which is the /var/lib/private EBUSY case that broke ntfy and gatus — an
#     impermanence entry bind-mounts the path systemd wants to manage and the
#     unit dies at STATE_DIRECTORY. Worse here than there: a dynamic UID also
#     means the ownership of persistent data changes under it across boots.
#     Forced off in favour of a static user, the shape services/prometheus.nix
#     already uses and explains.
#   * the cache contents go on /tank and are deliberately NOT added to
#     cosmos.system.impermanence.persist — /tank is a ZFS pool outside the
#     persist layer, so an entry there bind-mounts /persist over the top and
#     silently puts a growing binary cache on the 250 GB system SSD. The small
#     sqlite index is the opposite case and does get a persist entry.
{
  den,
  inputs,
  ...
}: {
  # The pull side, in roles.default so every host benefits — including
  # endeavour, which costs nothing there since it is the server.
  #
  # Inert until `publicKey` is set, and that is a sequencing fact rather than
  # an oversight: attic mints the cache's signing keypair when the cache is
  # *created*, at runtime, after the server is first deployed. There is no key
  # to write down until then. Deploy the server, run `atticd-atticadm` to make
  # the cache, then paste the public key into the option default below and
  # deploy the clients.
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

      # attic's CLI has no --config; it reads $XDG_CONFIG_HOME/attic/config.toml
      # and nothing else. Hence the runtime directory below with a symlink into
      # the rendered secret, rather than a path passed on the command line.
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
            # Merged with cache.nixos.org rather than displacing it. List order is
            # not what decides precedence — Nix sorts by the `priority` each cache
            # advertises in its nix-cache-info, and that number lives on the
            # server, not here: `attic cache configure lvdar --priority 39`.
            #
            # 39 against upstream's 40, so this one is tried *first* wherever it
            # has the path, and 404s fall through. It was 41 (upstream first)
            # until a CI run showed why that is the wrong way round on the mesh:
            # attic is a LAN hop, cache.nixos.org an internet one, and inside a
            # pipeline microVM the gap is wider still — attic arrives over the
            # host-side vsock proxy while upstream goes through slirp4netns.
            #
            # The cost lands on voyager away from home, which now asks an
            # unreachable cache first. connect-timeout and fallback below are
            # what bound that to five seconds rather than a hang.
            substituters = [cfg.endpoint];
            trusted-public-keys = [cfg.publicKey];

            # The cache is mesh-only, so voyager is regularly somewhere it cannot
            # be reached. Both of these are about that: fail over to building or
            # to cache.nixos.org quickly instead of hanging on a dead route.
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

            # A whole config file rather than a bare secret, because the CLI has
            # no flag for either the endpoint or the token — it reads both from
            # config.toml and nothing else.
            templates."attic-client.toml".content = ''
              default-server = "${cfg.cacheName}"

              [servers.${cfg.cacheName}]
              endpoint = "${cfg.serverUrl}/"
              token = "${config.sops.placeholder."keys/attic/push-token"}"
            '';
          };

          # So `attic push` is there for the cases watch-store cannot cover —
          # seeding above all. watch-store only uploads paths that appear after
          # it starts, so a store's existing contents reach the cache only by
          # being pushed by hand, and that is not hypothetical: it is how the
          # Discord blob whose upstream URL has since 404'd gets in.
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

              # The cache is mesh-only and voyager is often off the mesh, so this
              # unit failing is normal rather than exceptional. Restart forever
              # and quietly; do not let it reach the type-wide OnFailure ntfy
              # route in core/notify-failure.nix, which exists for things that
              # are actually wrong.
              Restart = "always";
              RestartSec = 30;

              # Uploading is not what this host is for.
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
        # Per-host, so no explicit sopsFile: core/sops.nix points
        # defaultSopsFile at hosts/<hostname>/secrets.yaml. Only the common
        # file needs naming, and this secret is used by exactly one host —
        # unlike keys/ntfy/password, which every host publishes with.
        #
        # A template rather than a bare secret because atticd wants an
        # EnvironmentFile, not a value: the same shape gatus.nix uses. systemd
        # opens it as root before dropping privileges, so no owner is needed.
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
            # Bound to every interface and firewalled to the mesh, the shape
            # kanidm and the arrs use here. NetBird assigns this host's mesh
            # address at enrollment, so it is not knowable at eval time.
            listen = "[::]:${toString cfg.port}";

            # Attic builds the URLs it hands to clients from this, so it must
            # be the name clients actually resolve — the mesh name, not
            # localhost. Mesh names work on this host only because
            # services/unbound.nix forwards the mesh domain to the NetBird
            # agent's resolver.
            api-endpoint = "http://${config.networking.hostName}.${dnsDomain}:${toString cfg.port}/";

            database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";

            storage = {
              type = "local";
              path = cfg.dataDir;
            };

            # Content-defined chunking is what makes this worth running over a
            # plain `nix copy` target: two closures that differ by one
            # derivation share the chunks of everything else, which matters
            # most for exactly the case this exists for — rebuilding pioneer's
            # aarch64 system closure over and over.
            #
            # The sizes are 16x upstream's, and that is a storage decision
            # rather than a dedup one. Every chunk costs a database transaction
            # and a synchronous file write, and /tank is two raidz1 vdevs of
            # spinning disks with no SLOG — so a sync write is a round trip
            # across a stripe, and the array sustains only a few per second.
            #
            # Measured before changing anything: ingest ran at ~150 KB/s on a
            # link that does 24 MB/s, about 2.3 chunks/second, with 202,982
            # chunks recorded for 6,437 NARs — 31 chunks for every store path.
            # A 2 GB CUDA closure at that rate takes four hours, which is what
            # made a push look hung rather than slow, and what starved
            # watch-store into 30-second pool timeouts.
            #
            # The dedup lost is small in the case this serves: the wins here
            # come from whole closures being reused across four hosts, not from
            # sub-megabyte overlap inside a NAR.
            #
            # nar-size-threshold is the bigger lever of the two. At 64 KiB
            # essentially every path was chunked; at 32 MiB the overwhelming
            # majority are stored whole and skip the machinery entirely.
            #
            # Only new uploads are affected — the existing chunks stay as they
            # are, so this improves things going forward rather than
            # retroactively.
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

        # The header explains why. Nested inside serviceConfig rather than at
        # the top of the aspect body on purpose — den unwraps priority wrappers
        # to classify aspect content, and a mkForce sitting at the top level
        # recurses infinitely alongside facter (see hosts/pioneer.nix).
        systemd.services.atticd.serviceConfig = {
          DynamicUser = lib.mkForce false;

          # PrivateUsers maps the service into its own user namespace, which is
          # harmless with a dynamic UID but hides the static one from the files
          # it owns on /tank.
          PrivateUsers = lib.mkForce false;

          # Refuse to start rather than fill the system SSD, the same guard and
          # the same reasoning as services/minecraft.nix.
          #
          # dataDir is its own dataset (see hosts/_hw/endeavour/disko.nix) whose
          # recordsize and sync settings are half of why uploads are not
          # glacial. If it is missing or unmounted the path still *exists* as a
          # directory on the pool root, so atticd would start happily, write
          # chunks with the wrong properties, and be slow again for reasons
          # nobody would think to look for.
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
