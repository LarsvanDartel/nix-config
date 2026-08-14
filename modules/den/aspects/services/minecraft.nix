# services.minecraft — Minecraft servers for friends, declared here rather than
# clicked into a panel.
#
# The deliberate choice this file encodes: no control panel. Pelican,
# Pterodactyl and Crafty are what most people reach for, and all three move the
# servers' state out of Nix and into a database that then has to be backed up,
# upgraded and secured on its own terms — plus none of them are packaged for
# NixOS. Here a server is an attribute in hosts/endeavour.nix, and adding,
# upgrading or retiring one is an edit and a deploy. Friends get an address and
# a whitelist entry; nobody else needs an account.
#
# Built on github:Infinidoge/nix-minecraft rather than nixpkgs'
# `services.minecraft-server`, which is singular and vanilla-only. The upstream
# module is plural, ships Paper/Fabric/Quilt/NeoForge/Purpur/Velocity through
# its overlay, and renders whitelist, ops, bans and server.properties from Nix.
# It also provides `fetchPackwizModpack`, which is what makes the mod set here
# a reviewable directory in this repo rather than a pile of pinned URLs.
# It also already carries a thorough systemd hardening block — unlike
# services/traccar.nix, the fleet's other hand-run JVM, this file adds none of
# its own, because duplicating it would only create a second owner of the same
# settings.
#
# Two things upstream does that matter to how this is wired:
#
#   * it creates the `minecraft` user with `home = dataDir; createHome = true`,
#     so the pool directory needs no tmpfiles rule of its own — but see the
#     mount guard below for what that hands us if the dataset is missing.
#   * per-server console is a local socket under /run/minecraft, not RCON.
#     RCON stays off; it is a plaintext remote-admin protocol and there is
#     nothing here it would buy. Which kind of socket is a decision this file
#     makes rather than inherits — see managementSystem below.
{
  den,
  inputs,
  ...
}: {
  flake-file.inputs.nix-minecraft.url = "github:Infinidoge/nix-minecraft";

  # The server packages live in the flake's overlay, not in nixpkgs. Registered
  # into the same aggregator modules/pkgs/*.nix uses (modules/meta/nixpkgs.nix),
  # which modules/den/overlays.nix composes into flake.overlays.default.
  nixpkgs.overlays = [
    inputs.nix-minecraft.overlays.default

    # Fixes an upstream bug: Fabric servers are launched with the wrong Java.
    #
    # Minecraft 26.2 is compiled for Java 25 (class file version 69). Upstream
    # gets this right for vanilla and Paper, which pick a JDK from the version
    # manifest and from Paper's documented requirements respectively — but
    # `mkTextileServer`, which builds the Fabric and Quilt launchers, takes
    # plain `jre_headless` out of the package set, and that is still Java 21.
    # The result starts, then dies immediately with
    #
    #   UnsupportedClassVersionError: net/minecraft/bundler/Main has been
    #   compiled by a more recent version of the Java Runtime (class file
    #   version 69.0) ... only recognizes class file versions up to 65.0
    #
    # which cost a rolled-back deploy to find. mkTextileServer is not exported
    # from the overlay, so it cannot simply be re-called with a different
    # `jre_headless`; instead this rebuilds the same one-line launcher with the
    # right JDK, reusing the loader derivation upstream already produced.
    #
    # Scoped to the one version this fleet runs, not mapped over the whole
    # attrset: older Minecraft versions genuinely want Java 17 or 21, and
    # forcing 25 on all of them would trade a loud failure for a quiet one.
    # Bumping the server version means bumping this too — the mismatch is a
    # crash loop at activation, not a silent misbehaviour, so it will say so.
    (_: prev: {
      fabricServers =
        prev.fabricServers
        // {
          fabric-26_2 = let
            vanilla = prev.vanillaServers.vanilla-26_2;
            inherit (prev.fabricServers.fabric-26_2.passthru) loader;
          in
            (prev.writeShellScriptBin "minecraft-server" ''
              exec ${prev.lib.getExe prev.jdk25_headless} \
                -D${loader.propertyPrefix}.gameJarPath=${vanilla}/lib/minecraft/server.jar \
                -Dlog4j.configurationFile=${inputs.nix-minecraft}/pkgs/fabric-servers/log4j.xml \
                "$@" -jar ${loader}/lib/minecraft/launch.jar nogui
            '')
            // rec {
              pname = "minecraft-server";
              version = "${vanilla.version}-${loader.loaderName}-${loader.loaderVersion}";
              name = "${pname}-${version}";
              passthru = {inherit loader;};
            };
        };
    })
  ];

  den.aspects.services.minecraft = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.attrsets) attrValues mapAttrs mapAttrs' nameValuePair;
      inherit (lib.options) mkOption;
      inherit (lib.types) attrsOf bool ints listOf nullOr oneOf package port str submodule;

      cfg = config.cosmos.services.minecraft;

      # The server-side performance set, resolved by packwiz against Minecraft
      # 26.2. Every entry earns its place on a server; nothing here is a client
      # rendering mod:
      #
      #   fabric-api        the dependency the rest are written against
      #   lithium           game-logic rewrites, all vanilla-behaviour-preserving
      #   ferritecore       cuts blockstate memory, the single biggest heap win
      #   krypton           network stack, cheaper packet handling
      #   c2me              parallel chunk I/O and generation
      #   scalablelux       the lighting engine off the main thread
      #   vmp               chunk and player tracking that scales past a handful
      #   alternate-current a redstone implementation that is orders faster
      #   servercore        tick and chunk-gen throttles under load
      #   spark             the profiler, so "it feels laggy" becomes a flamegraph
      #
      # Two of these are alpha upstream — c2me and scalablelux — and both touch
      # chunk storage and lighting, the parts of a world you least want a bug
      # in. They are here because the pool takes hourly snapshots, so the cost
      # of a bad chunk is a rollback rather than a lost world. Drop them from
      # the pack first if anything odd shows up.
      #
      # Deliberately absent: ModernFix and Noisium, which have no 26.2 build —
      # only third-party forks, which is not a dependency to take on a server
      # holding the only copy of something.
      defaultModpack = pkgs.fetchPackwizModpack {
        src = ./_minecraft/pack;
        packHash = "sha256-x6VFhJvf9vAOh2dSow4cJ5GOwpu2IGdtSTTpSmEFrmE=";
      };

      # The mods/ directory a given server gets: the shared packwiz pack, its
      # own extraMods, or both merged.
      #
      # The loose jars are wrapped in a directory first because symlinkJoin
      # joins *directories* — handed a bare file it would produce a store path
      # that is not a mods/ folder at all. The basename is stripped of its store
      # hash on the way in, so the server sees `voicechat-fabric-2.6.22.jar`
      # rather than `ps28hlg…-voicechat-fabric-2.6.22.jar`; Fabric does not care
      # about the filename, but anyone reading `ls mods/` on the host does.
      modsDir = s: let
        extraDir = pkgs.runCommand "minecraft-extra-mods" {} ''
          mkdir -p "$out"
          ${lib.concatMapStringsSep "\n" (m: ''
              name=$(basename ${m} | cut -d- -f2-)
              # Fabric loads *.jar and ignores anything else in silence, so a
              # mod that lost its extension produces a server that starts
              # cleanly and simply does not have the mod. Fail the build
              # instead — this caught simple-voice-chat, whose store path was
              # named from pname+version and had no suffix at all.
              case "$name" in
                *.jar) ;;
                *) echo "extraMods entry ${m} does not end in .jar" >&2; exit 1 ;;
              esac
              ln -s ${m} "$out/$name"
            '')
            s.extraMods}
        '';
      in
        if s.extraMods == []
        then "${s.modpack}/mods"
        else
          pkgs.symlinkJoin {
            name = "minecraft-mods";
            paths = lib.optional (s.modpack != null) "${s.modpack}/mods" ++ [extraDir];
          };

      # Aikar's flags — the G1GC tuning the Minecraft server community settled
      # on years ago and still the sane default. The point of them is pause
      # time, not throughput: a default-configured JVM will happily stop the
      # world for long enough that players see a rubber-band, and no amount of
      # CPU on this host fixes that. Heap is pinned (-Xms == -Xmx) on purpose;
      # a growing heap just means the collector re-learns its sizing mid-game.
      #
      # The >= 12 GiB branch is Aikar's own, not an invention here: larger
      # heaps want bigger regions and a larger young generation.
      aikarFlags = heapGiB: let
        large = heapGiB >= 12;
      in
        [
          "-Xms${toString heapGiB}G"
          "-Xmx${toString heapGiB}G"
          "-XX:+UseG1GC"
          "-XX:+ParallelRefProcEnabled"
          "-XX:MaxGCPauseMillis=200"
          "-XX:+UnlockExperimentalVMOptions"
          "-XX:+DisableExplicitGC"
          "-XX:+AlwaysPreTouch"
          "-XX:G1HeapWastePercent=5"
          "-XX:G1MixedGCCountTarget=4"
          "-XX:G1MixedGCLiveThresholdPercent=90"
          "-XX:G1RSetUpdatingPauseTimePercent=5"
          "-XX:SurvivorRatio=32"
          "-XX:+PerfDisableSharedMem"
          "-XX:MaxTenuringThreshold=1"
        ]
        ++ (
          if large
          then [
            "-XX:G1NewSizePercent=40"
            "-XX:G1MaxNewSizePercent=50"
            "-XX:G1HeapRegionSize=16M"
            "-XX:G1ReservePercent=15"
            "-XX:InitiatingHeapOccupancyPercent=20"
          ]
          else [
            "-XX:G1NewSizePercent=30"
            "-XX:G1MaxNewSizePercent=40"
            "-XX:G1HeapRegionSize=8M"
            "-XX:G1ReservePercent=20"
            "-XX:InitiatingHeapOccupancyPercent=15"
          ]
        );

      # Refuses to start rather than write a world to the wrong disk. See
      # requireMountedDataDir for why this exists at all.
      mountGuard = pkgs.writeShellApplication {
        name = "minecraft-datadir-guard";
        runtimeInputs = [pkgs.util-linux];
        text = ''
          if ! mountpoint -q ${lib.escapeShellArg cfg.dataDir}; then
            echo "${cfg.dataDir} is not a mount point — refusing to start." >&2
            echo "The ZFS dataset is missing or unmounted; starting anyway would" >&2
            echo "write worlds to the root subvolume, which impermanence wipes" >&2
            echo "at the next boot. Run: zfs create tank/minecraft" >&2
            exit 1
          fi
        '';
      };
    in {
      imports = [inputs.nix-minecraft.nixosModules.minecraft-servers];

      options.cosmos.services.minecraft = {
        dataDir = mkOption {
          type = str;
          default = "/tank/minecraft";
          description = ''
            Where the worlds live. One subdirectory per server.

            On the array rather than the 250 GB system SSD, which is the
            opposite of the call made for the spindle's VM images next door in
            services/tangled.nix — and for a reason worth stating, because the
            two look contradictory.

            What a Minecraft world actually needs is not throughput, it is
            *versions*. The realistic loss here is a creeper in spawn, a bad
            WorldEdit, or a griefer who was inside the whitelist — and against
            all three the fix is `zfs rollback` to an hourly snapshot, done in
            seconds. On the btrfs SSD there is no snapshot mechanism at all and
            restic's 02:00 copy would be the only version in existence.

            The array's weakness, random-read latency, barely applies: the
            working set is the handful of loaded region files, this host has
            64 GiB of ARC and a 500 GB L2ARC in front of the spindles, and
            saves are periodic batched writes rather than a random-write
            stream.

            Deliberately NOT added to cosmos.system.impermanence.persist —
            /tank is a ZFS pool outside the persist layer, and an entry there
            would bind-mount /persist over the top and silently move the worlds
            back onto the SSD. hosts/endeavour.nix documents that trap twice.
          '';
        };

        requireMountedDataDir = mkOption {
          type = bool;
          default = true;
          description = ''
            Refuse to start a server unless dataDir is a mount point.

            This guards the one failure mode here that is silent and
            destructive. Upstream creates the `minecraft` user with
            `createHome = true`, so if the ZFS dataset does not exist the
            directory is simply created on the root subvolume instead — the
            servers start, players connect, everything looks correct, and the
            worlds are on a filesystem that the impermanence rollback erases at
            the next boot. An ExecStartPre check turns that into a unit that
            fails loudly on day one.
          '';
        };

        servers = mkOption {
          default = {};
          description = ''
            Servers to run. The aspect owns the policy that a *public* port
            demands; the host names the instances and picks versions.
          '';
          type = attrsOf (submodule {
            options = {
              deferRestart = mkOption {
                type = bool;
                default = false;
                description = ''
                  Stage configuration changes instead of applying them: deploy
                  writes the new unit, and the running server keeps its old
                  settings until it next stops on its own.

                  For changing settings while people are playing. Most of
                  server.properties is only read at startup, so there is no way
                  to apply it live — but there is a difference between "takes
                  effect at the next restart" and "disconnects everyone now",
                  and on a hardcore world that difference can be someone's run.
                  The next restart is usually the 02:00 restic quiesce, which
                  was going to happen anyway.

                  Upstream's `enableReload` looks like the option for this and
                  is not: its ExecReload runs ExecStopPost then ExecStartPre,
                  which deletes and recreates the managed files — including the
                  mods symlink — underneath a live JVM, and still would not
                  apply a startup-only property.

                  Turn it back off once the change has landed. Left on, it
                  makes every future edit to this server silently not take
                  effect, which is exactly the kind of quiet divergence between
                  the repo and reality this fleet is built to avoid.
                '';
              };

              port = mkOption {
                type = port;
                default = 25565;
                description = ''
                  TCP listener. Also the port gaia publishes, so a second
                  server needs a second one here and a matching entry in
                  hosts/gaia.nix.
                '';
              };

              heapGiB = mkOption {
                type = ints.positive;
                default = 6;
                description = ''
                  JVM heap, fixed (-Xms == -Xmx). Generous against this host's
                  64 GiB, and the reason there is no MemoryMax anywhere near
                  this unit: the heap is the bound, and a cgroup cap on top
                  would turn a GC pause into an OOM kill. No service in this
                  repo uses cgroup caps — contention is handled by scheduling.
                '';
              };

              package = mkOption {
                type = package;
                default = pkgs.fabricServers.fabric-26_2;
                defaultText = "pkgs.fabricServers.fabric-26_2";
                description = ''
                  Server jar. Fabric rather than Paper, and the trade is worth
                  stating because Paper is the more usual answer.

                  Paper optimises by *changing the game* — its patches alter
                  redstone, entity and chunk behaviour, and it silently
                  rewrites the world into its own split-dimension layout, which
                  is a one-way door. Fabric leaves vanilla semantics alone and
                  moves the optimisation into mods that can be added and
                  removed one at a time. For a server whose whole point is
                  playing vanilla with friends, keeping vanilla behaviour and
                  choosing the optimisations explicitly is the better shape —
                  and the modpack option below is what makes it competitive.

                  Pinned to a version alias, NOT a bare `fabric` alias. Version
                  aliases here resolve to prereleases: `pkgs.paperServers.paper`
                  pointed at 26.2-rc-2-build.9 when this was written, and
                  fabricServers carries a full set of `-pre-N` and `-snapshot-N`
                  entries alongside the release. Other people have to update
                  their clients to match this line, so it moves deliberately.
                '';
              };

              modpack = mkOption {
                type = nullOr package;
                default = defaultModpack;
                defaultText = "the packwiz pack in ./_minecraft/pack";
                description = ''
                  A fetchPackwizModpack derivation whose mods/ directory is
                  symlinked into the server. Null for no mods.

                  packwiz rather than a hand-rolled list of fetchurl calls
                  because it is the format the Minecraft world already uses:
                  `packwiz modrinth add <slug>` resolves the right build for
                  the pack's Minecraft version and writes the URL and hash into
                  a .pw.toml, and `packwiz update` re-resolves them. The pack
                  is a directory in this repo rather than a URL, so the mod set
                  is reviewable in a diff and pinned by packHash — nothing is
                  fetched at deploy time that was not fetched at build time.

                  Symlinked, not copied: upstream's `files` are writable and
                  deleted when the server stops, `symlinks` are read-only store
                  paths. Mods are the store's business, so a mod cannot be
                  changed on the running host and quietly diverge from what
                  this repo says is deployed.
                '';
              };

              extraMods = mkOption {
                type = listOf package;
                default = [];
                example = "[pkgs.simple-voice-chat]";
                description = ''
                  Jars to add to this server on top of `modpack`.

                  The pack above is deliberately shared by every server, since
                  it exists to carry the performance mods all of them want. This
                  is the escape hatch for a mod that belongs to *one* world —
                  voice chat on the hardcore server and not on the survival one.
                  Adding it to the pack instead would install it everywhere.

                  Each entry is a derivation producing a single .jar. They are
                  merged with the pack's mods/ into one directory that is
                  symlinked in, so the same read-only-store property holds:
                  nothing here can be edited on the running host.

                  Note this bypasses packwiz, so `packwiz update` will not see
                  these and the Minecraft version compatibility is on you —
                  which is why the pack remains the right home for anything
                  every server should have.
                '';
              };

              motd = mkOption {
                type = str;
                default = "lvdar.nl";
                description = "Line shown in the client's server list.";
              };

              whitelist = mkOption {
                type = attrsOf str;
                default = {};
                example = {lvdar = "00000000-0000-0000-0000-000000000000";};
                description = ''
                  Player name → UUID. Enforced, so an empty whitelist means a
                  server nobody can join — which is the right way round for a
                  port that is open to the internet.

                  Upstream validates the UUID format, so a typo fails the build
                  rather than producing a whitelist that silently omits someone.
                '';
              };

              operators = mkOption {
                type = attrsOf str;
                default = {};
                description = "Player name → UUID, granted permission level 4.";
              };

              serverProperties = mkOption {
                type = attrsOf (oneOf [bool ints.unsigned str]);
                default = {};
                example = {
                  difficulty = "hard";
                  max-players = 10;
                };
                description = ''
                  Extra server.properties entries, merged over the defaults
                  below. The security-relevant ones are set by the aspect and
                  can be overridden from here — deliberately possible, but do
                  read what the defaults are for first.
                '';
              };
            };
          });
        };
      };

      config = {
        services.minecraft-servers = {
          enable = true;
          eula = true;
          inherit (cfg) dataDir;

          # The mesh exposure below is what makes these reachable, and it is
          # the only path that should exist. Letting upstream open the port
          # would put a game server on endeavour's LAN interface as well, for
          # no one's benefit.
          openFirewall = false;

          # Console over a systemd socket rather than upstream's default tmux
          # session, and the reason is logging, not taste.
          #
          # Under tmux the unit is Type=forking and the server's stdout goes to
          # the tmux pane. Measured on the first deploy: the journal held
          # exactly two lines for this unit — "Starting" and "Started" — while
          # the entire server log sat in the world directory where nothing
          # reads it. services/alloy.nix ships the journal to loki, so that
          # arrangement means a Minecraft server is the one thing on this fleet
          # you cannot grep in Grafana, and the OnFailure notification tells
          # you a unit died with no way to see why.
          #
          # systemd-socket puts stdout in the journal and takes commands on a
          # group-writable FIFO instead:
          #
          #   journalctl -fu minecraft-server-smp
          #   echo 'whitelist add SomeName' > /run/minecraft/smp.stdin
          #
          # The loss is an interactive session; with the log in the journal
          # there is not much of one to miss.
          managementSystem = {
            tmux.enable = false;
            systemd-socket.enable = true;
          };

          servers =
            mapAttrs (_: s: {
              enable = true;
              inherit (s) package whitelist;

              jvmOpts = aikarFlags s.heapGiB;

              operators = mapAttrs (_: uuid: {inherit uuid;}) s.operators;

              # One mods/ directory, whatever it is made of. symlinkJoin rather
              # than two entries because upstream's `symlinks` is keyed by path
              # — there is exactly one mods/ and it can only point at one place.
              symlinks = lib.optionalAttrs (s.modpack != null || s.extraMods != []) {
                mods = modsDir s;
              };

              serverProperties =
                {
                  server-port = s.port;
                  motd = s.motd;

                  # The three that matter on a public port, and the reason
                  # they are here rather than left to the host:
                  #
                  #   online-mode      — verifies logins against Mojang. False
                  #                      means anyone may join as any username,
                  #                      including as an operator.
                  #   white-list       — the allow-list itself.
                  #   enforce-whitelist— kicks players who are already on when
                  #                      they fall off the list. Without it the
                  #                      whitelist only gates new joins.
                  white-list = true;
                  enforce-whitelist = true;
                  online-mode = true;

                  # Plaintext remote admin, and the console is already
                  # available as a group-gated socket on the host.
                  enable-rcon = false;

                  # The legacy UDP query protocol. Off: it is a reflection
                  # amplification source and nothing here reads it.
                  enable-query = false;
                }
                // s.serverProperties;
            })
            cfg.servers;
        };

        systemd.services = mapAttrs' (name: s:
          nameValuePair "minecraft-server-${name}" {
            serviceConfig.ExecStartPre =
              lib.mkIf cfg.requireMountedDataDir
              [(lib.getExe mountGuard)];

            # mkForce because upstream already defines this as
            # `!conf.enableReload`, and two plain definitions of the same
            # option conflict. Nested inside an attribute rather than at the
            # top of the aspect body, which is where a mkForce recurses under
            # facter — see the comment in hosts/pioneer.nix.
            restartIfChanged = lib.mkForce (!s.deferRestart);
          })
        cfg.servers;

        # Reachable from gaia over WireGuard, and from nowhere else — gaia is
        # the only host with a public address, so this is the whole of the
        # ingress path on this side. A port missing here is a published service
        # that times out rather than one that fails loudly.
        cosmos.services.netbird.client.exposedPorts =
          map (s: s.port) (attrValues cfg.servers);

        # Nothing is wired for monitoring on purpose. Unit failures already
        # notify through the type-wide OnFailure drop-in in
        # core/notify-failure.nix, and the server's stdout reaches loki through
        # services/alloy.nix by virtue of being in the journal — which is true
        # only because of the managementSystem choice above, not by default. A
        # per-service exporter would be the first in the fleet and would earn
        # nothing.
      };
    };
  };
}
