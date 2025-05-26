{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) str;
  inherit (lib.modules) mkIf mkDefault;

  cfg = config.modules.git;
in {
  imports = [
    ./lazygit.nix
  ];

  options.modules.git = {
    enable = mkEnableOption "git";
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

  config = mkIf cfg.enable {
    modules.git.lazygit.enable = mkDefault true;
    modules.terminal.shell.aliases = {
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

    programs.git = {
      enable = true;
      userName = cfg.user;
      userEmail = cfg.email;

      delta = {
        inherit (cfg.delta) enable;
        options = {
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
      };

      extraConfig = {
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
        branch = {
          sort = "-committerdate";
        };
        tag = {
          sort = "-taggerdate";
        };
        url = {
          "git@github.com:${cfg.user}/".insteadOf = "${config.home.username}:";
          "git@github.com:".insteadOf = "gh:";
        };
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
    };
  };
}
