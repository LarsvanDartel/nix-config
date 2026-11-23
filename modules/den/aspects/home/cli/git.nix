# home.git — git with identity from cosmos options, ssh signing and allowed_signers
{cosmosLib, ...}: let
  inherit (cosmosLib) get-flake-path;

  baseSettings = {
    advice = {
      addEmptyPathspec = false;
      pushNonFastForward = false;
      statusHints = false;
    };
    core = {
      compression = 9;
      whitespace = "error";
    };
    status = {
      branch = true;
      showStash = true;
    };
    diff = {
      context = 3;
      rename = "copies";
      interHunkContext = 10;
    };
    push = {
      autosetupRemote = true;
      default = "current";
      followTags = true;
    };
    pull = {
      default = "current";
      rebase = true;
    };
    rebase = {
      autoStash = true;
      missingCommitsCheck = "warn";
    };
    log = {
      abbrevCommit = true;
      graphColors = "blue,yellow,cyan,magenta,green,red";
    };
    init.defaultBranch = "main";
    fetch.prune = true;
    branch.sort = "-committerdate";
    tag.sort = "-taggerdate";
    color = {
      diff = {
        # Not black: that is base00, the terminal background, in both modes.
        meta = "brightblack bold";
        frag = "magenta";
        context = "white";
        whitespace = "yellow reverse";
        old = "red";
      };
      decorate = {
        HEAD = "red";
        branch = "blue";
        tag = "yellow";
        remoteBranch = "magenta";
      };
      branch = {
        current = "magenta";
        local = "default";
        remote = "yellow";
        upstream = "green";
        plain = "blue";
      };
    };
  };

  deltaOptions = {
    features = "unobtrusive-line-numbers decorations";
    whitespace-error-style = "22 reverse";
    decorations = {
      commit-decoration-style = "bold yellow box ul";
      file-decoration-style = "none";
      file-style = "bold yellow ul";
    };
    line-numbers = true;
    line-numbers-left-format = "{nm:>4}┊";
    line-numbers-right-format = "{np:>4}│";
    line-numbers-left-style = "blue";
    line-numbers-right-style = "blue";
  };
in {
  den.aspects.home.git.homeManager = {
    config,
    osConfig,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.types) str;
    inherit (lib.strings) fileContents;

    cfg = config.cosmos.cli.programs.git;
    publicKey = "${config.cosmos.user.home}/.ssh/id_${osConfig.networking.hostName}.pub";

    # `git agent-pull [branch]`: the agent's commits from endeavour, re-authored
    # (and re-signed) as this user on top of the current branch.
    agentPull = pkgs.writeShellApplication {
      name = "git-agent-pull";
      runtimeInputs = [config.programs.git.package];
      text = ''
        target=$(git symbolic-ref --quiet --short HEAD) || {
          echo "git agent-pull: check out the branch to pull into" >&2
          exit 1
        }
        branch=''${1:-$target}

        if ! git remote get-url agent >/dev/null 2>&1; then
          git remote add agent "ssh://agent@endeavour:2222/home/agent/dev/$(basename "$(git rev-parse --show-toplevel)")"
        fi
        git fetch agent
        tip=$(git rev-parse "agent/$branch")
        mark=refs/agent-pull/$branch

        # The agent's branch keeps every commit it ever made; patch-id misses
        # ones whose context moved here, so take only what follows the last pull.
        if last=$(git rev-parse --verify --quiet "$mark") && git merge-base --is-ancestor "$last" "$tip"; then
          [[ $last == "$tip" ]] && {
            echo "git agent-pull: nothing new on agent/$branch"
            exit 0
          }
          range=(--onto "$target" "$last")
        else
          range=("$target")
        fi

        if ! git rebase --empty=drop \
          --exec "git merge-base --is-ancestor HEAD $target || git commit --amend --no-edit --reset-author" \
          "''${range[@]}" "$tip"; then
          echo "git agent-pull: after the rebase finishes: git switch $target && git merge --ff-only 'HEAD@{1}' && git update-ref $mark $tip" >&2
          exit 1
        fi
        rewritten=$(git rev-parse HEAD)
        git switch --quiet "$target"
        git merge --ff-only "$rewritten"
        git update-ref "$mark" "$tip"
      '';
    };
  in {
    options.cosmos.cli.programs.git = {
      user = mkOption {
        type = str;
        default = "LarsvanDartel";
        description = "User name for git";
      };
      email = mkOption {
        type = str;
        default = "larsvandartel73@gmail.com";
        description = "User email for git";
      };
      delta.enable = mkEnableOption "delta" // {default = true;};
    };

    config = {
      cosmos.cli.shells.zsh.aliases = {
        gs = "git status --short";
        gd = "git diff";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gu = "git pull";
        gl = "git log --all --graph --pretty=format:'%C(magenta)%h %C(white) %an  %ar%C(auto)  %D%n%s%n'";
        gb = "git branch";
        gi = "git init";
        gcl = "git clone";
      };

      home.packages = [agentPull];

      programs.delta = {
        inherit (cfg.delta) enable;
        options = deltaOptions;
      };

      programs.git = {
        enable = true;
        ignores = [".direnv" "result"];
        settings =
          baseSettings
          // {
            user = {
              name = cfg.user;
              inherit (cfg) email;
            };
            url = {
              "git@github.com:${cfg.user}".insteadOf = "lvdar";
              "git@github.com:".insteadOf = "gh:";
            };
            gpg.ssh.allowedSignersFile = "${config.cosmos.user.home}/.ssh/allowed_signers";
          };

        # Only where home.ssh places this host's device key.
        signing = lib.mkIf (lib.elem osConfig.networking.hostName config.cosmos.cli.programs.ssh.identities) {
          signByDefault = true;
          key = publicKey;
          format = "ssh";
        };
      };

      # The second key is a retired id_voyager key; it keeps older signatures verifiable.
      home.file.".ssh/allowed_signers".text = ''
        ${cfg.email} ${fileContents (get-flake-path "modules/den/aspects/core/_ssh-keys/id_voyager.pub")}
        ${cfg.email} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDNEUz9gdN7GD8a1BNijKPl+3/CwYr+n36G4FjvqqVTt
      '';
    };
  };
}
