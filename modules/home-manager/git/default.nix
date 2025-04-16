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
    programs.git = {
      enable = true;
      userName = cfg.user;
      userEmail = cfg.email;

      extraConfig = {
        pull.rebase = true;
        init.defaultBranch = "main";
        fetch.prune = true;
      };
    };
  };
}
