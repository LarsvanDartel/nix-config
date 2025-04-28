{
  config,
  lib,
  ...
}: let
  cfg = config.modules.git;
in {
  imports = [
    ./lazygit.nix
  ];

  options.modules.git = {
    enable = lib.mkEnableOption "git";
    user = lib.mkOption {
      type = lib.types.str;
      description = "User name for git";
    };
    email = lib.mkOption {
      type = lib.types.str;
      description = "User email for git";
    };
  };

  config = lib.mkIf cfg.enable {
    modules.git.lazygit.enable = lib.mkDefault true;
    modules.shell.aliases = {
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

      diff-so-fancy = {
        enable = true;
        markEmptyLines = false;
        stripLeadingSymbols = true;
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
