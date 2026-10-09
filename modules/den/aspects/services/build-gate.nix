# services.build-gate — nothing reaches the fleet until it has been built.
#
# comin has no magic rollback, so comin tracks `deploy`, never `main`: on
# every push to main this builds all x86_64 hosts and fast-forwards `deploy`
# only if all are green. `git log deploy..main` is "what has not passed yet".
# On the metal, not the spindle microVM (76 min there vs 4m36s native).
# Does not gate flake-bump, which already builds all hosts before committing.
{
  den,
  inputs,
  ...
}: {
  den.aspects.services.build-gate = {
    includes = [den.aspects.core.sops];

    nixos = {
      config,
      pkgs,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) listOf str path;

      cfg = config.cosmos.services.build-gate;

      script = pkgs.writeShellApplication {
        name = "build-gate";
        runtimeInputs = with pkgs; [git openssh nix coreutils];
        text = ''
          repo=${cfg.stateDir}/repo

          # --quiet everywhere for the same reason flake-bump does it: git
          # writes transfer progress to stderr with no tty attached and alloy
          # ships this journal to loki.
          export GIT_TERMINAL_PROMPT=0
          export GIT_SSH_COMMAND="ssh -i ${cfg.sshKeyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

          if [ ! -d "$repo/.git" ]; then
            echo "cloning ${cfg.repository}"
            git clone --quiet ${cfg.repository} "$repo"
          fi
          cd "$repo"

          git remote set-url origin ${cfg.repository}
          git fetch --quiet origin ${cfg.sourceBranch} ${cfg.deployBranch} || \
            git fetch --quiet origin ${cfg.sourceBranch}

          head=$(git rev-parse "origin/${cfg.sourceBranch}")
          deployed=$(git rev-parse "origin/${cfg.deployBranch}" 2>/dev/null || echo none)

          if [ "$head" = "$deployed" ]; then
            echo "${cfg.deployBranch} already at $head; nothing to verify"
            exit 0
          fi

          echo "verifying $head (${cfg.deployBranch} at $deployed)"

          # Detached at the revision under test rather than checked out as a
          # branch: this clone is a scratch space and should never have an
          # opinion about what it is tracking.
          git checkout --quiet --detach "$head"
          git clean -qfdx

          failed=""
          for host in ${lib.concatStringsSep " " cfg.hosts}; do
            echo "=== building $host ==="
            # nix-secrets is a private git+ssh input this unit holds no key
            # for, and the stub is sound because sops-nix runs with
            # validateSopsFiles = false — nothing reads it at eval time. Same
            # reasoning as flake-bump and the old CI workflows.
            #
            # No --print-build-logs: this journal goes to loki, and a full
            # three-host build's builder output is tens of MB of it.
            if ! nix build \
                --accept-flake-config \
                --no-write-lock-file \
                --override-input nix-secrets ./.tangled/nix-secrets-stub \
                --no-link \
                ".#nixosConfigurations.$host.config.system.build.toplevel"; then
              failed="$failed $host"
            fi
          done

          if [ -n "$failed" ]; then
            echo "build failed for:$failed — ${cfg.deployBranch} stays at $deployed" >&2
            exit 1
          fi

          # --force-with-lease rather than --force: if deploy moved while this
          # was building, something else is publishing to it and clobbering
          # that is not this unit's call.
          git push --quiet --force-with-lease origin "$head:refs/heads/${cfg.deployBranch}"
          echo "green — ${cfg.deployBranch} $deployed -> $head"
        '';
      };
    in {
      options.cosmos.services.build-gate = {
        repository = mkOption {
          type = str;
          example = "git@git.example.org:me/nix-config";
          description = ''
            Pushed over SSH to the knot rather than written into the bare repo
            on disk, even though this host *is* the knot host. Writing to
            /tank/git directly would move the ref while leaving the appview
            showing nothing: the knot emits sh.tangled.git.refUpdate from its
            own receive path, not from a git hook.
          '';
        };

        sourceBranch = mkOption {
          type = str;
          default = "main";
          description = "Where work lands, and what this verifies.";
        };

        deployBranch = mkOption {
          type = str;
          default = "deploy";
          description = ''
            Where verified work lands, and the only thing comin should follow.

            Advanced by this unit alone. If it is behind ${"main"}, that is not
            drift — it is a build that has not passed, or has not run yet.
          '';
        };

        hosts = mkOption {
          type = listOf str;
          default = ["gaia" "endeavour" "voyager"];
          description = ''
            Must all build before deploy moves. The three x86_64 ones; pioneer
            is aarch64 and this host cannot emulate it, which is the same
            reason it was left out of the workflows this replaces.

            voyager is included even though comin does not deploy it: it is
            still a host whose closure this repo has to keep evaluable, and
            catching that here is cheaper than catching it at `nh os switch`.
          '';
        };

        watchPath = mkOption {
          type = path;
          example = "/srv/git/<repo>/refs/heads/main";
          description = ''
            The knot's ref file for the source branch. A plain file whose mtime
            moves on every push, which is what makes this event-driven rather
            than a poll — see the systemd.paths unit below.

            A literal path into the knot's storage, and therefore the fragile
            part of this aspect: it hardcodes a DID and the knot's on-disk
            layout, neither of which is knowable from this host's config. If a
            push stops triggering a build, this is the first thing to check.
          '';
        };

        sshKeyFile = mkOption {
          type = str;
          default = config.sops.secrets."keys/flake-bump/ssh-key".path;
          defaultText = "the flake-bump sops secret";
          description = ''
            Shared with flake-bump rather than given its own, because tangled
            has no per-repo deploy keys — a key is an sh.tangled.publicKey
            record on an ATProto identity and grants push to every repo that
            identity owns. A second key would be a second thing to rotate for
            exactly the same access.
          '';
        };

        stateDir = mkOption {
          type = str;
          default = "/var/lib/build-gate";
          description = ''
            Working clone, kept between runs so a verification is a fetch and
            an incremental build rather than a clone and a cold one. That reuse
            is most of why this takes minutes.
          '';
        };
      };

      config = {
        sops.secrets."keys/flake-bump/ssh-key" = {
          sopsFile = builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";
          mode = "0400";
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.stateDir} 0700 root root - -"
        ];

        cosmos.system.impermanence.persist.directories = [
          {
            directory = cfg.stateDir;
            user = "root";
            group = "root";
            mode = "0700";
          }
        ];

        systemd.services.build-gate = {
          description = "Build every host at main, and advance deploy if green";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe script;
            # Three closures matter less than the Minecraft servers and the array.
            Nice = 10;
            IOSchedulingClass = "idle";
          };
        };

        systemd.paths.build-gate = {
          wantedBy = ["multi-user.target"];
          pathConfig = {
            # PathChanged, not PathModified: git writes the new ref to a lock
            # file and renames it over the old one — a replacement, not a write.
            PathChanged = cfg.watchPath;
            # Catch a push that happened while this host was down. Without it
            # the gate silently skips whatever landed during a reboot.
            MakeDirectory = false;
            Unit = "build-gate.service";
          };
        };

        # A push during a build would otherwise be lost — the path unit cannot
        # queue, only note the service is running. The timer closes that; the
        # script exits immediately when deploy already matches main.
        systemd.timers.build-gate = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "5m";
            OnUnitInactiveSec = "15m";
            RandomizedDelaySec = "2m";
          };
        };
      };
    };
  };
}
