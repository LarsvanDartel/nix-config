# services.minecraft — Minecraft servers for friends, declared here rather than
# clicked into a panel.
#
# Deliberately no control panel (Pelican/Pterodactyl/Crafty move state into a
# database outside Nix). Built on nix-minecraft rather than nixpkgs'
# singular, vanilla-only services.minecraft-server; its systemd hardening is
# not duplicated here. RCON stays off; console is a local socket.
{
  den,
  inputs,
  ...
}: {
  flake-file.inputs.nix-minecraft.url = "github:Infinidoge/nix-minecraft";

  # The packwiz packs (pkgs.modpacks.<pack>), in their own repository so they
  # are released and edited apart from the fleet. Public HTTPS, not git@knot:
  # build-gate has no SSH credential. Run `nix run .#write-flake` after editing.
  flake-file.inputs.modpacks = {
    url = "git+https://knot.lvdar.nl/did:plc:lz6wnhglzbatsbxadexhf3bx?shallow=1";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  nixpkgs.overlays = [
    inputs.nix-minecraft.overlays.default
    inputs.modpacks.overlays.default
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

      # Loose jars are wrapped in a directory because symlinkJoin joins
      # directories, not files; the store hash is stripped from basenames.
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

      # Aikar's flags: G1GC tuned for pause time. Heap pinned (-Xms == -Xmx).
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

      # Refuses to start rather than write a world to the wrong disk.
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
                  server needs a second one here and a matching
                  netbird-service entry from the host.
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
                example = "pkgs.neoforgeServers.neoforge-1_21_1-21_1_259";
                description = ''
                  Server jar. Its Minecraft and loader versions must match the
                  modpack's pack.toml `[versions]`; nothing checks that for
                  you, and a mismatch is a crash at startup.

                  Pin a fully versioned alias, NOT a bare `neoforge`/`fabric`
                  alias. Bare aliases here resolve to prereleases:
                  `pkgs.paperServers.paper` pointed at 26.2-rc-2-build.9 once,
                  and the loader sets carry `-pre-N` and `-snapshot-N` entries
                  alongside releases. Other people have to update their
                  clients to match this line, so it moves deliberately.
                '';
              };

              modpack = mkOption {
                type = nullOr package;
                default = null;
                example = "pkgs.modpacks.create.server";
                description = ''
                  A pack's server tree from the modpacks input
                  (`pkgs.modpacks.<pack>.server`). Null for no mods. Must
                  match `package` (see there).

                  packwiz because it is the format the Minecraft world already
                  uses: `packwiz modrinth add <slug>` resolves the right build
                  for the pack's Minecraft version and writes the URL and hash
                  into a .pw.toml, and every file is fetched against that
                  hash — nothing is fetched at deploy time that was not
                  fetched at build time. packs.lvdar.nl (minecraft-packs.nix)
                  serves players the same revision.

                  mods/ is symlinked, not copied: upstream's `files` are
                  writable and deleted when the server stops, `symlinks` are
                  read-only store paths. Mods are the store's business, so a
                  mod cannot be changed on the running host and quietly
                  diverge from what is deployed. Every other top-level entry
                  (config/, ...) goes through `files`, because mods rewrite
                  their configs at startup and crash on a read-only one.
                '';
              };

              extraMods = mkOption {
                type = listOf package;
                default = [];
                example = "[(pkgs.fetchurl {name = \"mod.jar\"; ...})]";
                description = ''
                  Jars to add to this server on top of `modpack`: the escape
                  hatch for a mod that belongs to this world but not the pack
                  players install.

                  Each entry is a derivation producing a single .jar. They are
                  merged with the pack's mods/ into one directory that is
                  symlinked in, so the same read-only-store property holds:
                  nothing here can be edited on the running host.

                  Note this bypasses packwiz, so `packwiz update` will not see
                  these and the Minecraft version compatibility is on you —
                  which is why the pack remains the right home for anything
                  players need too.
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

          # Mesh exposure only; no game server on endeavour's LAN interface.
          openFirewall = false;

          # systemd-socket, not tmux: under tmux stdout never reaches the
          # journal, so the server log is invisible to loki and failure
          # notifications. Console: echo 'cmd' > /run/minecraft/<name>.stdin
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

              # One symlinkJoin: upstream's `symlinks` is keyed by path, so
              # mods/ can only point at one place.
              symlinks = lib.optionalAttrs (s.modpack != null || s.extraMods != []) {
                mods = modsDir s;
              };

              files = lib.optionalAttrs (s.modpack != null) (lib.genAttrs
                (lib.remove "mods" (s.modpack.topLevel or []))
                (entry: "${s.modpack}/${entry}"));

              serverProperties =
                {
                  server-port = s.port;
                  motd = s.motd;

                  # enforce-whitelist kicks online players removed from the
                  # list; without it the whitelist only gates new joins.
                  white-list = true;
                  enforce-whitelist = true;
                  online-mode = true;

                  enable-rcon = false;

                  # Legacy UDP query: a reflection amplification source.
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

            # mkForce: upstream defines this as `!conf.enableReload`. Nested,
            # not at aspect top level, where mkForce recurses under facter
            # (see hosts/pioneer.nix).
            restartIfChanged = lib.mkForce (!s.deferRestart);
          })
        cfg.servers;

        cosmos.services.netbird.client.exposedPorts =
          map (s: s.port) (attrValues cfg.servers);
      };
    };
  };
}
