# services.flake-bump — the scheduled half of "keep the lock fresh".
#
# tangled has exactly three trigger kinds — push, pull_request, manual — so
# "periodically" cannot be a workflow. `.tangled/workflows/flake-update.yml` is
# the same work in a form you can fire by hand; this is the timer, and it is
# the one that commits.
#
# What it does, once a day: update every flake input, build the three x86_64
# hosts, and push the new lock to main only if all three are green. comin then
# picks it up within five minutes and the fleet moves itself. If anything is
# red the lock is reverted and the unit exits non-zero, which reaches ntfy
# through the type-wide OnFailure drop-in in core/notify-failure.nix — no
# separate notifier, and a failure that cannot be missed.
#
# Three things about this that are load-bearing:
#
#   * **nix-secrets is excluded from the update.** Everything else here is
#     public; that one is a private git+ssh input and this host has no key for
#     it. Builds use the same empty stub CI uses, which is sound for the same
#     reason — sops-nix runs with validateSopsFiles = false, so nothing reads
#     it. See .tangled/nix-secrets-stub/flake.nix.
#   * **Only flake.lock is committed.** Never a tree the timer has otherwise
#     touched. If the working copy is dirty for any reason the run aborts.
#   * **It pushes over SSH to the knot, not into the bare repo on disk.**
#     endeavour *is* the knot host, so writing to /tank/git directly would be
#     tempting and wrong: the knot emits sh.tangled.git.refUpdate from its own
#     receive path rather than from a git hook (hooks/post-receive.d is empty),
#     so a filesystem push would move the ref while leaving CI untriggered and
#     the appview showing nothing.
#
# The consequence worth stating plainly: an upstream change can now reach two
# production hosts unattended, and comin has no magic rollback. The gate is
# that all three hosts must build first — which, with abort-on-warn, is a
# stronger gate than it sounds, since a deprecation warning anywhere is a
# failure. It is not a guarantee that the result behaves.
{
  den,
  inputs,
  ...
}: {
  den.aspects.services.flake-bump = {
    includes = [den.aspects.core.sops];

    nixos = {
      config,
      pkgs,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) listOf str;

      cfg = config.cosmos.services.flake-bump;

      script = pkgs.writeShellApplication {
        name = "flake-bump";
        runtimeInputs = with pkgs; [git openssh nix jq coreutils gnugrep];
        text = ''
          repo=${cfg.stateDir}/repo
          export GIT_SSH_COMMAND="ssh -i ${cfg.sshKeyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

          if [ ! -d "$repo/.git" ]; then
            echo "cloning ${cfg.repository}"
            git clone --branch ${cfg.branch} ${cfg.repository} "$repo"
          fi
          cd "$repo"

          git remote set-url origin ${cfg.repository}
          git fetch origin ${cfg.branch}
          git checkout ${cfg.branch}
          git reset --hard origin/${cfg.branch}
          git clean -fdx -e result

          # Refuse to run on a tree that is not exactly upstream. The commit
          # below is `git commit flake.lock`, so anything else lying around
          # would not be committed — but it could still change what gets built,
          # which would make a green result mean nothing.
          if [ -n "$(git status --porcelain)" ]; then
            echo "working tree is dirty after reset; refusing" >&2
            exit 1
          fi

          before=$(git rev-parse HEAD)

          # Every root input except nix-secrets, which is a private git+ssh
          # remote this host holds no key for. Enumerated from the lock rather
          # than hardcoded, so a new input is picked up without editing this.
          mapfile -t inputs < <(
            nix flake metadata --json --accept-flake-config \
              | jq -r '.locks.nodes.root.inputs | keys[]' \
              | grep -vx 'nix-secrets'
          )
          echo "updating ''${#inputs[@]} inputs"
          nix flake update --accept-flake-config "''${inputs[@]}"

          if git diff --quiet flake.lock; then
            echo "lock unchanged; nothing to do"
            exit 0
          fi

          echo "lock moved:"
          git --no-pager diff --stat flake.lock

          failed=""
          for host in ${lib.concatStringsSep " " cfg.hosts}; do
            echo "=== building $host ==="
            if ! nix build \
                --accept-flake-config \
                --no-write-lock-file \
                --override-input nix-secrets ./.tangled/nix-secrets-stub \
                --print-build-logs --no-link \
                ".#nixosConfigurations.$host.config.system.build.toplevel"; then
              failed="$failed $host"
            fi
          done

          if [ -n "$failed" ]; then
            echo "build failed for:$failed — reverting the lock" >&2
            git checkout flake.lock
            exit 1
          fi

          # Separate -m flags rather than one string with embedded blank
          # lines: an indented Nix string would otherwise have to contain
          # column-zero lines, which the formatter reindents — silently
          # rewriting the commit message every time anyone runs `nix fmt`.
          git -c user.name="${cfg.gitName}" -c user.email="${cfg.gitEmail}" \
            commit flake.lock \
            -m "chore(flake): update lock" \
            -m "Automated by services.flake-bump on $(hostname)." \
            -m "${lib.concatStringsSep ", " cfg.hosts} all built green against this lock before it was committed."

          git push origin ${cfg.branch}
          echo "pushed $before -> $(git rev-parse HEAD)"
        '';
      };
    in {
      options.cosmos.services.flake-bump = {
        repository = mkOption {
          type = str;
          default = "git@knot.lvdar.nl:lvdar.nl/nix-config";
          description = ''
            Push target. SSH rather than the HTTPS URL comin reads, because
            this end writes — and it goes through the knot's own receive path
            so the ref update is published and CI fires.

            Note this pushes only to the knot. The GitHub mirror lags until
            your next manual push; giving this a second credential to keep the
            mirror in step was not judged worth it.
          '';
        };

        branch = mkOption {
          type = str;
          default = "main";
          description = ''
            Where the bump lands. `main` means comin deploys it unattended
            within the poll interval. Setting this to `testing` instead makes
            comin `test`-activate it — active now, gone at the next reboot,
            which is the cautious variant if a nightly unattended switch ever
            turns out to be too much.
          '';
        };

        hosts = mkOption {
          type = listOf str;
          default = ["gaia" "endeavour" "voyager"];
          description = ''
            Hosts that must build before the lock is committed. The three
            x86_64 ones; pioneer is aarch64 and this host cannot emulate it,
            the same reason CI leaves it out.
          '';
        };

        sshKeyFile = mkOption {
          type = str;
          default = config.sops.secrets."keys/flake-bump/ssh-key".path;
          defaultText = "the flake-bump sops secret";
          description = ''
            Private key allowed to push to the knot.

            Tangled has no per-repo deploy keys — a key is an
            sh.tangled.publicKey record on your ATProto identity, so this grants
            push to every repo you own on the knot. That is the smallest thing
            that can do the job, not a small thing; it is why the aspect exists
            on one host and nowhere else.
          '';
        };

        stateDir = mkOption {
          type = str;
          default = "/var/lib/flake-bump";
          description = "Working clone. Kept between runs so a bump is a fetch, not a full clone.";
        };

        schedule = mkOption {
          type = str;
          default = "04:00";
          description = ''
            After restic at 02:00 and clear of the nightly Minecraft restart,
            so three host builds are not competing with the backup for the
            array.
          '';
        };

        gitName = mkOption {
          type = str;
          default = "flake-bump";
          description = "Author on the generated commit — deliberately not a human's name.";
        };

        gitEmail = mkOption {
          type = str;
          default = "flake-bump@lvdar.nl";
          description = "Author email on the generated commit.";
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

        systemd.services.flake-bump = {
          description = "Update flake.lock, build every host, push if green";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe script;
            # Builds three NixOS closures; the array and the Minecraft servers
            # matter more than this finishing quickly.
            Nice = 10;
            IOSchedulingClass = "idle";
          };
        };

        systemd.timers.flake-bump = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.schedule;
            Persistent = true;
            RandomizedDelaySec = "30m";
          };
        };
      };
    };
  };
}
