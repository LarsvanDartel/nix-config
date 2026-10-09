# services.tangled — a self-hosted Tangled knot: git repositories addressed by
# ATProto identity rather than by an account on someone else's forge.
#
# SSH arrives as gaia :22 forwarded to :2222 here, never :22: NetBird redirects
# <mesh-ip>:22 to its own SSH server (see core/ssh.nix).
# The knot appends a `Match User git` block to sshd_config, so anything later
# added to `services.openssh.extraConfig` lands inside that Match block.
{
  den,
  inputs,
  ...
}: {
  flake-file.inputs.tangled.url = "git+https://tangled.org/tangled.org/core";

  den.aspects.services.tangled = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.tangled;
    in {
      imports = [inputs.tangled.nixosModules.knot];

      options.cosmos.services.tangled = {
        owner = mkOption {
          type = str;
          example = "did:plc:xxxxxxxxxxxxxxxxxxxxxxxx";
          description = ''
            The DID that owns this knot, from the Tangled settings page.

            No default on purpose: a knot registered to the wrong identity looks
            like it works right up until it refuses every push, so this should
            fail the build rather than guess.
          '';
        };

        hostname = mkOption {
          type = str;
          default = "knot.lvdar.nl";
          description = ''
            Public name. Covered by the existing *.lvdar.nl wildcard in
            services/acme.nix, so it needs no certificate work — and it must
            match what gaia publishes, since the knot signs its registration
            with this name.
          '';
        };

        port = mkOption {
          type = port;
          default = 5555;
          description = "HTTP listener, reached over the mesh by netbird-proxy.";
        };

        stateDir = mkOption {
          type = str;
          example = "/srv/git";
          description = ''
            Repositories and the knot's SQLite database.

            On the array rather than the module's /home/git default: these are
            the canonical copy of the code, and the 250 GB system SSD already
            carries every other service's state. Being on /tank also means
            sanoid snapshots cover them.

            Deliberately NOT added to cosmos.system.impermanence.persist — /tank
            is a ZFS pool outside the persist layer, and an entry there would
            bind-mount /persist over the top and silently move the repositories
            back onto the SSD. hosts/endeavour.nix documents that trap twice.
          '';
        };
      };

      config = {
        # No KNOT_SERVER_SECRET in this version: registration is proved by the
        # owner DID, so no sops secret. If a release reintroduces one, add it here.

        systemd.tmpfiles.rules = [
          "d ${cfg.stateDir} 0755 git git - -"
        ];

        services.tangled.knot = {
          enable = true;
          inherit (cfg) stateDir;

          server = {
            owner = cfg.owner;
            hostname = cfg.hostname;
            listenAddr = "0.0.0.0:${toString cfg.port}";
          };

          openFirewall = false;
        };

        # 2222: gaia DNATs public :22 here in the kernel (hosts/gaia.nix), not
        # via netbird-proxy. Without it the SSH hop hangs with no banner.
        cosmos.services.netbird.client.exposedPorts = [cfg.port 2222];
      };
    };
  };

  # The CI runner, separate so a host can carry repositories without building them.
  den.aspects.services.tangled.spindle = {
    includes = [
      den.aspects.services.tangled
      den.aspects.services.attic.client
    ];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) ints port str;

      cfg = config.cosmos.services.tangled;
      sCfg = cfg.spindle;

      # Upstream's guest (4 GiB, 2 vCPUs, 24 GiB disk) OOMs and runs out of disk
      # on a NixOS closure. Only spec.json is rewritten; the rest is symlinked.
      # The disk volume is the build's whole writable surface; limits.total.diskMiB
      # is only a scheduler budget and never resizes a guest.
      guestImage =
        pkgs.runCommand "spindle-nixos-image-${toString sCfg.guestMemoryMiB}mib" {
          nativeBuildInputs = [pkgs.jq];
        } ''
          base=${inputs.tangled.packages.${pkgs.stdenv.hostPlatform.system}.spindle-nixos-image}
          mkdir -p "$out"
          jq '.memoryMiB = ${toString sCfg.guestMemoryMiB}
              | .vcpus = ${toString sCfg.guestVcpus}
              | .volumes |= map(.sizeMiB = ${toString sCfg.guestDiskMiB})' \
            "$base/spec.json" > "$out/spec.json"
          ln -s "$base/kernel"     "$out/kernel"
          ln -s "$base/initrd"     "$out/initrd"
          ln -s "$base/store-disk" "$out/store-disk"
        '';
    in {
      imports = [inputs.tangled.nixosModules.spindle];

      options.cosmos.services.tangled.spindle = {
        hostname = mkOption {
          type = str;
          default = "spindle.lvdar.nl";
          description = "Public name, covered by the existing *.lvdar.nl wildcard.";
        };

        guestMemoryMiB = mkOption {
          type = ints.positive;
          default = 16384;
          description = ''
            RAM given to each pipeline microVM, in MiB (16 GiB).

            Upstream ships 4 GiB, which OOMs partway through evaluating a NixOS
            system. This is sized against what actually has to fit — a nix
            evaluation of a full host closure — and against what this host can
            spare: two concurrent workflows is 32 GiB of the 62 here, alongside
            two Minecraft servers holding 6 GiB heaps each. limits.total below
            is what stops that arithmetic from being merely optimistic.

            Raised from 12 GiB together with guestVcpus: nix defaults max-jobs
            to the core count, so quadrupling the vCPUs quadruples how many
            builders can be resident at once, and memory has to follow or the
            first thing the extra parallelism buys is an OOM.
          '';
        };

        guestDiskMiB = mkOption {
          type = ints.positive;
          default = 65536;
          description = ''
            Writable volume inside each pipeline microVM, in MiB (64 GiB).

            Upstream ships 24 GiB, which holds gaia's closure and not
            endeavour's. This is the nix store, the eval cache and the
            workspace combined, so it has to fit a whole NixOS system with the
            build's intermediates on top.

            64 GiB is deliberately generous against ~25 GiB of real usage: the
            overlay is sparse and thrown away per run, so the declared size
            costs nothing until it is used. What it does cost is a ceiling —
            two guests could in principle want 128 GiB against the ~186 GB free
            on this SSD. If that ever becomes real rather than theoretical, the
            move is to point pipelines.microvm.overlayDir at /tank, which has a
            terabyte spare and trades latency for room.
          '';
        };

        guestVcpus = mkOption {
          type = ints.positive;
          default = 32;
          description = ''
            vCPUs per pipeline microVM.

            Upstream ships 2. This host has 72 threads and a nix build is the
            most parallel workload it runs, so 2 is leaving most of the machine
            idle while CI is the thing you are waiting on.

            32 rather than 8, which was itself a conservative first guess made
            before anything had run: two guests at this size is 64 of 72
            threads, leaving the host eight for jellyfin, immich and two live
            Minecraft servers. The ceiling that keeps that true is
            limits.total below, not this.
          '';
        };

        imageDir = mkOption {
          type = str;
          default = "/var/lib/spindle/images";
          description = ''
            Where the microVM guest images live, and where the tmpfiles rule
            below links the NixOS one into.

            On the SSD and persisted, unlike the overlays: an image is
            expensive to build — a whole NixOS guest, kernel and store disk —
            and re-fetching one after every reboot would be a slow first
            pipeline for no benefit.
          '';
        };

        port = mkOption {
          type = port;
          default = 6555;
          description = "Free on this host; reached over the mesh by netbird-proxy.";
        };

        stateDir = mkOption {
          type = str;
          example = "/srv/spindle";
          description = ''
            Repository checkouts only. The VM images and overlays deliberately
            do NOT live here — see below.

            Checkouts are bulk and mostly sequential, which is what the array is
            good at, and they are the part that grows without a bound anyone
            chose.

            Not added to persist.directories: /tank is outside the persist layer
            and an entry would bind-mount /persist over it. See the knot above.
          '';
        };

        workflowTimeout = mkOption {
          type = str;
          default = "120m";
          description = ''
            Wall clock a single workflow gets, covering the wait for a
            concurrency slot, image setup and every step in it.

            The module's default is 5 minutes, which is fine for the `go test`
            pipelines tangled itself runs and is not remotely enough here — a
            cold `nix build` of this fleet's NixOS systems is tens of minutes
            even with the cache below. The failure is also an unhelpful one:
            the workflow is marked `timeout` mid-build, with nothing in the log
            pointing at configuration.

            Two hours rather than one because a run measured 46 minutes just to
            *reach* the third host with a cold cache, which left voyager — the
            largest of the three — nowhere near enough room. This is a ceiling
            and not a cost: a workflow that finishes in eight minutes is
            unaffected, and the number only matters on the runs that would
            otherwise be killed with no useful diagnostic.
          '';
        };
      };

      config = {
        systemd.tmpfiles.rules = [
          "d ${sCfg.stateDir} 0750 root root - -"

          # Nothing populates imageDir by default, and an empty one fails every
          # workflow silently (visible only in the pipeline status record).
          # Interpolating the derivation keeps the image a GC root.
          "L+ ${sCfg.imageDir}/nixos - - - - ${guestImage}"
        ];

        services.tangled.spindle = {
          enable = true;

          server = {
            owner = cfg.owner;
            hostname = sCfg.hostname;
            listenAddr = "0.0.0.0:${toString sCfg.port}";
            repoDir = "${sCfg.stateDir}/repos";

            # Upstream's default 127.0.0.1:9091 collides with transmission on
            # endeavour, crash-looping the spindle. 9501: see services/node-exporter.nix.
            metricsListenAddr = "127.0.0.1:9501";
          };

          pipelines.microvm = {
            # On the SSD, not the raidz array: VM boots and overlays are random I/O.
            inherit (sCfg) imageDir;

            # overlayDir stays at the /tmp default: SSD, wiped at boot.
            # Totals are two guests' worth, matching maxJobCount, so a third
            # workflow queues instead of overcommitting the host.
            limits.total = {
              memoryMiB = 2 * sCfg.guestMemoryMiB;
              vcpus = 2 * sCfg.guestVcpus;
              diskMiB = 2 * sCfg.guestDiskMiB;
            };
          };

          pipelines.workflowTimeout = sCfg.workflowTimeout;

          # Any non-empty bucket registers the S3 store (artifactstore.go:173)
          # without checking credentials, adding ~19 s of EC2 IMDS timeouts per run.
          artifactStores.s3.bucket = "";

          # Works despite the sandbox blackholing 100.64.0.0/10: the spindle
          # proxies substituter reads host-side over vsock. Read from the attic
          # client options; do not add a third copy of the URL and key.
          pipelines.nixCache = {
            readUrls = [config.cosmos.services.attic.client.endpoint];
            trustedPublicKeys =
              lib.lists.optional
              (config.cosmos.services.attic.client.publicKey != null)
              config.cosmos.services.attic.client.publicKey;

            # uploadUrl deliberately unset: "daemon" would let a fork's
            # pull_request pipeline push paths into the fleet's cache.
          };
        };

        # Host-side vsock, not loaded by default; without it every workflow fails
        # with "listen vsock host(2):10240: bind: cannot assign requested address".
        boot.kernelModules = ["vhost_vsock"];

        # The module hardcodes SPINDLE_MILL_ARTIFACT_STORE=s3, so finished logs
        # are lost. mkAfter: systemd takes the last assignment of a repeated variable.
        systemd.services.spindle.serviceConfig.Environment =
          lib.mkAfter ["SPINDLE_MILL_ARTIFACT_STORE=disk"];

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/spindle";
            user = "root";
            group = "root";
            mode = "0750";
          }
        ];

        cosmos.services.netbird.client.exposedPorts = [sCfg.port];
      };
    };
  };
}
