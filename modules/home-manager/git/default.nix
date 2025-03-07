{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.git;
in {
  options.modules.git = {
    enable = lib.mkEnableOption "Enable Git";
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
    home.packages = with pkgs; [
      git
      lazygit
    ];

    programs.git = {
      enable = true;
      userName = cfg.user;
      userEmail = cfg.email;

      extraConfig = {
        pull.rebase = true;
        init.defaultBranch = "main";
      };
    };
  };
}
