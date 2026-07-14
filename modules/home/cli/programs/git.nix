# git. The identity/host-independent settings are factored into `baseSettings`,
# shared by two modules:
#   - `flake.modules.homeManager.git`: portable wrapper. Identity is injected via
#     the `gitIdentity` specialArg; no SSH commit signing / allowed_signers (those
#     are host-specific and don't belong in a `nix run .#git` build).
#   - `flake.modules.homeManager.common`: the full deployment config (identity from
#     cosmos options, signing, allowed_signers, shell aliases).
{cosmosLib, ...}: let
  inherit (cosmosLib) get-flake-path;

  # Everything that doesn't depend on who you are or which host you're on.
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
        meta = "black bold";
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

  # `lvdar`/`gh:` shorthands depend on the resolved github user.
  mkUrl = user: {
    "git@github.com:${user}".insteadOf = "lvdar";
    "git@github.com:".insteadOf = "gh:";
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

  ignores = [
    ".direnv"
    "result"
  ];
in {
  flake.modules.homeManager.git = {gitIdentity, ...}: {
    programs.delta = {
      enable = true;
      options = deltaOptions;
    };

    programs.git = {
      enable = true;
      inherit ignores;
      settings =
        baseSettings
        // {
          user = {
            name = gitIdentity.user;
            inherit (gitIdentity) email;
          };
          url = mkUrl gitIdentity.user;
        };
    };
  };

  flake.modules.homeManager.common = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.types) str;
    inherit (lib.strings) fileContents;

    cfg = config.cosmos.cli.programs.git;
    publicKey = "${config.cosmos.user.home}/.ssh/id_voyager.pub";
  in {
    options.cosmos.cli.programs.git = {
      user = mkOption {
        type = str;
        description = "User name for git";
      };
      email = mkOption {
        type = str;
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

      programs.delta = {
        inherit (cfg.delta) enable;
        options = deltaOptions;
      };

      programs.git = {
        enable = true;
        inherit ignores;
        settings =
          baseSettings
          // {
            user = {
              name = cfg.user;
              inherit (cfg) email;
              signingkey = publicKey;
            };
            url = mkUrl cfg.user;
            gpg.format = "ssh";
            gpg.ssh.allowedSignersFile = "${config.cosmos.user.home}/.ssh/allowed_signers";
            commit.gpgsign = true;
          };

        signing = {
          signByDefault = true;
          key = publicKey;
          format = "openpgp";
        };
      };

      home.file.".ssh/allowed_signers".text = ''
        ${cfg.email} ${fileContents (get-flake-path "modules/nixos/services/ssh/keys/id_voyager.pub")}
      '';
    };
  };
}
