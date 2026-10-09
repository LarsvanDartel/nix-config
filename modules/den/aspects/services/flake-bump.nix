# services.flake-bump — the scheduled half of "keep the lock fresh".
#
# Daily: update every input, build the three x86_64 hosts, push the lock to
# main only if all are green (comin then deploys). tangled has no scheduled
# trigger, so this timer is the only way; run on demand with
# `systemctl start flake-bump` rather than reintroducing a workflow copy.
#
#   * nix-secrets is excluded: private git+ssh input with no key here; builds
#     use .tangled/nix-secrets-stub (sound because validateSopsFiles = false).
#   * Push over SSH to the knot, never into /tank/git directly: the knot emits
#     refUpdate from its receive path, not a hook, so a filesystem push would
#     leave CI untriggered.
#   * Upstream changes reach production unattended; the gate is only that all
#     three hosts build (with abort-on-warn).
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

          # git writes transfer progress to stderr even with no tty, and the
          # first run put ~400 lines of "Receiving objects: 43%" into the
          # journal — which alloy then ships to loki. Every git call below is
          # --quiet for that reason; the interesting output is what this script
          # echoes itself.
          export GIT_TERMINAL_PROMPT=0
          export GIT_SSH_COMMAND="ssh -i ${cfg.sshKeyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

          if [ ! -d "$repo/.git" ]; then
            echo "cloning ${cfg.repository}"
            git clone --quiet --branch ${cfg.branch} ${cfg.repository} "$repo"
          fi
          cd "$repo"

          git remote set-url origin ${cfg.repository}
          git fetch --quiet origin ${cfg.branch}
          git checkout --quiet ${cfg.branch}
          git reset --quiet --hard origin/${cfg.branch}
          git clean -qfdx -e result

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
          #
          # The host name is interpolated at eval time, not read with
          # `hostname` at run time. It was the latter until now, and every
          # commit the timer has ever made says "on ." — `hostname` is not in
          # runtimeInputs and the unit's PATH does not supply it, so the
          # substitution expanded to nothing. `set -e` cannot catch that: the
          # status of a substitution inside an argument is discarded, so the
          # run stayed green and wrote a message missing the one fact it
          # existed to record. This form cannot fail that way — a typo here is
          # an eval error, not a blank.
          git -c user.name="${cfg.gitName}" -c user.email="${cfg.gitEmail}" \
            commit flake.lock \
            -m "chore(flake): update lock" \
            -m "Automated by services.flake-bump on ${config.networking.hostName}." \
            -m "${lib.concatStringsSep ", " cfg.hosts} all built green against this lock before it was committed."

          git push origin ${cfg.branch}
          echo "pushed $before -> $(git rev-parse HEAD)"
        '';
      };
    in {
      options.cosmos.services.flake-bump = {
        repository = mkOption {
          type = str;
          example = "git@git.example.org:me/nix-config";
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
          example = "flake-bump@example.org";
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
            # Yield to the array and Minecraft servers.
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
