{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.git;
in {
  options.git = {
    enable = mkEnableOption "Enable Git";
    user = mkOption {
      type = types.str;
      description = "User name for git";
    };
    email = mkOption {
      type = types.str;
      description = "User email for git";
    };
  };

  config = mkIf cfg.enable {
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
      };
    };
  };
}
