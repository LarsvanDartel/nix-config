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
  nixpkgs.overlays = [inputs.nix-minecraft.overlays.default];

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
      inherit (lib.types) attrsOf bool ints oneOf package port str submodule;

      cfg = config.cosmos.services.minecraft;

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
                default = pkgs.paperServers.paper-26_2;
                defaultText = "pkgs.paperServers.paper-26_2";
                description = ''
                  Server jar. Paper rather than vanilla: same gameplay, much
                  better chunk and entity performance, and plugins if they are
                  ever wanted.

                  Pinned to a version alias, NOT the bare `pkgs.paperServers.
                  paper` — that alias currently resolves to 26.2-rc-2-build.9,
                  a release candidate, and would hand a friends server whatever
                  prerelease upstream last saw. `paper-26_2` tracks stable
                  builds within 26.2 and moves only when this line does, which
                  is what you want when other people have to update their
                  clients to match.
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

        systemd.services = mapAttrs' (name: _:
          nameValuePair "minecraft-server-${name}" {
            serviceConfig.ExecStartPre =
              lib.mkIf cfg.requireMountedDataDir
              [(lib.getExe mountGuard)];
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
