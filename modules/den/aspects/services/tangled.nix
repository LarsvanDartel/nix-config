# services.tangled — a self-hosted Tangled knot: git repositories addressed by
# ATProto identity rather than by an account on someone else's forge.
#
# A knot is the part that actually holds the code. Identity, issues and pull
# requests live as ATProto records; the knot serves git over HTTP and SSH and
# answers to a DID. That is the whole reason this is worth running: the repos
# are on the array here, and the social layer is data rather than a database in
# a company.
#
# Two halves reach this host, and they arrive very differently:
#
#   HTTP   :5555, over the mesh, published by gaia's netbird-proxy like every
#          other service.
#   SSH    port 22 on gaia, forwarded at L4 to *:2222 here — deliberately not
#          :22. NetBird's agent redirects <mesh-ip>:22 to its own embedded SSH
#          server (core/ssh.nix documents this at length), so a forward to :22
#          would reach that instead of OpenSSH and every git push would fail
#          with a host key warning and "Permission denied (password)".
#
# The knot does not run an SSH daemon of its own. It appends a `Match User git`
# block with an AuthorizedKeysCommand to the system sshd, which is why nothing
# here touches ports or authentication: root key auth, deploy-rs and :2222 are
# all untouched. One consequence worth knowing — anything that later adds to
# `services.openssh.extraConfig` lands *inside* that Match block, because
# nixpkgs appends extraConfig to the end of sshd_config.
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
          default = "/tank/git";
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
        # No sops secret and no environmentFile. The module sets every KNOT_*
        # variable from its own options, and this version has no
        # KNOT_SERVER_SECRET — registration is proved by the owner DID plus the
        # `verify` button on tangled.org/settings/knots, not by a shared secret.
        # An env file was planned here and dropped once that turned out to be
        # true; if a future release reintroduces one, this is where it goes.

        # The module points the git user's home at stateDir and creates it, but
        # the parent has to exist on the pool first — same shape as loki.nix.
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

          # sshd already opens 22 and 2222 for the whole fleet, and the mesh
          # exposure below is what actually matters. Letting this module also
          # manage the firewall would just add a second owner of the same rule.
          openFirewall = false;
        };

        # Reachable from gaia over WireGuard, and from nowhere else. Note the
        # public :22 half does NOT come through here — netbird-proxy's L4 mode
        # would not forward to this target, so gaia DNATs it in the kernel
        # instead (hosts/gaia.nix).
        #
        # 2222 as well as the HTTP port, because the knot's *other* half arrives
        # that way: gaia publishes public :22 as an L4 service and forwards it
        # here, to OpenSSH on 2222 rather than 22 (see the header). Without this
        # the forward connects to gaia and then hangs with no banner — the mesh
        # is up, the knot answers on 5555, and only the SSH hop is filtered.
        # sshd already listens on 2222 fleet-wide; this is purely the mesh ACL.
        cosmos.services.netbird.client.exposedPorts = [cfg.port 2222];
      };
    };
  };

  # The CI runner. Separate aspect so a host can carry repositories without
  # also volunteering to build them, but it `includes` the knot: the owner DID
  # is declared there, and a spindle with no knot to serve is not a
  # configuration this fleet has a use for.
  den.aspects.services.tangled.spindle = {
    includes = [
      den.aspects.services.tangled
      # For the binary cache below. roles.default already pulls this in on
      # every host, so this is belt and braces — but the spindle reads the
      # client's options directly, and a dependency you read should be a
      # dependency you declare.
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

      # The guest image, resized — memory, vCPUs and disk.
      #
      # Upstream's image declares 4096 MiB, 2 vCPUs and a 24 GiB writable
      # volume in its spec.json. Those suit the `go test` pipelines tangled
      # runs on it and none of them survive a NixOS closure; both failures were
      # found by running it, one after the other:
      #
      #   guest out of memory (process 'nix' killed by guest kernel OOM)
      #   mkdir: cannot create directory '…-unit-loki.service':
      #     No space left on device
      #
      # The second one is the subtler of the two. That 24 GiB volume is the
      # *whole* writable surface of the build — nix store, eval cache and
      # workspace together — so gaia's closure fits and endeavour's does not.
      # `limits.total.diskMiB` below looks like it governs this and does not:
      # it is a scheduler budget across concurrent workflows and never resizes
      # a guest.
      #
      # Only the spec is rewritten, not the image. All three are arguments QEMU
      # is launched with, so the kernel, initrd and store disk are reused
      # verbatim by symlink — a few kilobytes of jq rather than a second NixOS
      # guest build, and it stays correct across an input bump because it
      # patches whatever upstream produced rather than reimplementing it.
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
          default = 12288;
          description = ''
            RAM given to each pipeline microVM, in MiB (12 GiB).

            Upstream ships 4 GiB, which OOMs partway through evaluating a NixOS
            system. 12 GiB is sized against what actually has to fit — a nix
            evaluation of a full host closure — and against what this host can
            spare: two concurrent workflows is 24 GiB of the 62 here, alongside
            two Minecraft servers holding 6 GiB heaps each. limits.total below
            is what stops that arithmetic from being merely optimistic.
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
          default = 8;
          description = ''
            vCPUs per pipeline microVM.

            Upstream ships 2. This host has 72 threads and a nix build is the
            most parallel workload it runs, so 2 is leaving most of the machine
            idle while CI is the thing you are waiting on.
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
          default = "/tank/spindle";
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
          # Enough for the pool; the module creates the leaf directories itself.
          "d ${sCfg.stateDir} 0750 root root - -"

          # The microVM guest image, and nothing provides it by default — the
          # NixOS module exposes `imageDir` as "directory containing microVM
          # image spec JSONs" and then leaves filling it to the operator. An
          # empty directory is not a loud failure: the spindle starts happily,
          # accepts pushes, creates pipelines, and fails every workflow in the
          # same second with
          #
          #   init workflow: microVM image "nixos" was not found;
          #   looked in: /var/lib/spindle/images/nixos, …/nixos.json
          #
          # which is only visible in the pipeline status record, not the
          # journal. Discovered by reading the spindle's own database after the
          # first real push produced three instant failures and no logs.
          #
          # `L+` replaces whatever is there, so a version bump of the tangled
          # input relinks rather than colliding. Interpolating the derivation
          # here also puts it in this host's system closure, which is what
          # keeps `nix-collect-garbage` from deleting a live CI image — a bare
          # symlink under /var/lib would not be a GC root.
          "L+ ${sCfg.imageDir}/nixos - - - - ${guestImage}"
        ];

        services.tangled.spindle = {
          enable = true;

          server = {
            owner = cfg.owner;
            hostname = sCfg.hostname;
            listenAddr = "0.0.0.0:${toString sCfg.port}";
            repoDir = "${sCfg.stateDir}/repos";
          };

          pipelines.microvm = {
            # Images and overlays stay on the SSD, and this is the one place in
            # this repo where that is the *performance* answer rather than the
            # convenient one. The array is six SAS spindles in two raidz1 vdevs:
            # good at sequential bulk, poor at the random reads a VM boot does
            # and the small random writes a copy-on-write overlay does. A SATA
            # SSD wins that profile by an order of magnitude on latency.
            #
            # Persisted, unlike the overlays: an image is expensive to fetch or
            # build, and now that the rollback actually works an unpersisted
            # cache would be re-fetched after every reboot.
            inherit (sCfg) imageDir;

            # overlayDir is left at the module's default of /tmp, which on this
            # host is the root subvolume — so overlays are on the SSD *and*
            # impermanence discards them at every boot. For scratch that is
            # exactly right; the only reason to move it to /tank would be
            # space, and limits.total below is what keeps that from arising.
            #
            # Ceilings on what the scheduler may have in flight at once, so
            # raising the per-guest figures above cannot quietly become an
            # overcommit of the host. All three are exactly two guests' worth,
            # matching maxJobCount — the scheduler queues a third workflow
            # rather than starting it, which is the behaviour you want when the
            # alternative is the host swapping, or filling its root filesystem,
            # while two Minecraft servers are live on it.
            limits.total = {
              memoryMiB = 2 * sCfg.guestMemoryMiB;
              vcpus = 2 * sCfg.guestVcpus;
              diskMiB = 2 * sCfg.guestDiskMiB;
            };
          };

          pipelines.workflowTimeout = sCfg.workflowTimeout;

          # Let pipelines read from the fleet's own binary cache.
          #
          # This looks like it should be impossible: the microVM sandbox
          # blackholes every RFC 6890 special-use range, which includes the
          # 100.64.0.0/10 the mesh lives on, precisely so a workflow cannot
          # reach the host or anything private. It works because the guest does
          # not connect to the cache at all — the spindle proxies substituter
          # reads host-side over vsock, and endeavour is where atticd runs.
          #
          # Worth having rather than a nicety: a NixOS closure built entirely
          # from cache.nixos.org is tens of minutes of downloading, and most of
          # what CI needs has already been built by voyager and pushed here.
          #
          # Read from the client aspect's options rather than repeating the URL
          # and key, which is a rule this repo has broken before — the values
          # in services/attic.nix are already literals kept in sync by hand
          # because den cannot read another host's config, and a third copy
          # would be a third thing to forget.
          pipelines.nixCache = {
            readUrls = [config.cosmos.services.attic.client.endpoint];
            trustedPublicKeys =
              lib.lists.optional
              (config.cosmos.services.attic.client.publicKey != null)
              config.cosmos.services.attic.client.publicKey;

            # uploadUrl deliberately unset. Pushing CI output back into attic
            # would make the next deploy instant, but it needs a write token,
            # and a cache that CI can write to is a cache that a bad pipeline
            # can poison. Worth revisiting once the read path has proven itself.
          };
        };

        # The host half of vsock, which is how the spindle talks to the agent
        # inside each microVM — and how the binary cache proxy above reaches
        # the guest without giving it network access to this host.
        #
        # Not loaded by default here. The modules that *were* loaded are all
        # guest-side transports (vsock_loopback, vmw_vsock_*), which is exactly
        # the sort of thing that makes `lsmod | grep vsock` look reassuring
        # while the host cannot listen at all. Without this every workflow dies
        # in setup with
        #
        #   listen vsock host(2):10240: bind: cannot assign requested address
        #
        # /dev/vhost-vsock existing is not evidence to the contrary; the device
        # node is there regardless.
        boot.kernelModules = ["vhost_vsock"];

        # Send finished workflow logs to the local disk store instead of S3.
        #
        # The module hardcodes SPINDLE_MILL_ARTIFACT_STORE=s3 with no option to
        # change it, while also exposing artifactStores.disk.dir — so archiving
        # always fails here with an AWS credential error, and the appview loses
        # the logs of any workflow that has finished, because that is exactly
        # when it switches from tailing the file to reading the artifact store.
        # mkAfter to land after the module's own list; systemd takes the last
        # assignment of a repeated Environment= variable.
        systemd.services.spindle.serviceConfig.Environment =
          lib.mkAfter ["SPINDLE_MILL_ARTIFACT_STORE=disk"];

        # The job database and the tap state. Small, and worth keeping across a
        # rollback so a reboot does not lose the record of what ran.
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
