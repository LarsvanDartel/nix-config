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
    in {
      imports = [inputs.tangled.nixosModules.spindle];

      options.cosmos.services.tangled.spindle = {
        hostname = mkOption {
          type = str;
          default = "spindle.lvdar.nl";
          description = "Public name, covered by the existing *.lvdar.nl wildcard.";
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

        diskLimitMiB = mkOption {
          type = ints.unsigned;
          default = 61440;
          description = ''
            Ceiling on total microVM disk usage, in MiB (60 GiB).

            The module's default is 0, meaning unlimited. That is tolerable when
            the images sit on a 1.4 TB array and genuinely is not when they sit
            on the 233 GB system SSD: a runaway build filling the root
            filesystem takes the host down, not just the job. 60 GiB against
            ~187 GB free leaves room for the system to keep working while a
            build misbehaves.
          '';
        };

        workflowTimeout = mkOption {
          type = str;
          default = "60m";
          description = ''
            Wall clock a single workflow gets, covering the wait for a
            concurrency slot, image setup and every step in it.

            The module's default is 5 minutes, which is fine for the `go test`
            pipelines tangled itself runs and is not remotely enough here — a
            cold `nix build` of this fleet's NixOS systems is tens of minutes
            even with the cache below. The failure is also an unhelpful one:
            the workflow is marked `timeout` mid-build, with nothing in the log
            pointing at configuration.
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
          "L+ ${sCfg.imageDir}/nixos - - - - ${inputs.tangled.packages.${pkgs.stdenv.hostPlatform.system}.spindle-nixos-image}"
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

            # Left at the module's default of /tmp, which on this host is the
            # root subvolume — so overlays are on the SSD *and* impermanence
            # discards them at every boot. For scratch that is exactly right;
            # the only reason not to would be space, which diskLimitMiB bounds.
            limits.total.diskMiB = sCfg.diskLimitMiB;
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
