{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) bool;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.yazi;
in {
  options.cosmos.cli.programs.yazi = {
    enable = mkEnableOption "yazi file manager";
    defaultApplication = mkOption {
      type = bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    cosmos.cli.shells.zsh.aliases = {
      "y" = "${pkgs.yazi}/bin/yazi";
    };
    programs.yazi = {
      enable = true;
      enableZshIntegration = config.cosmos.cli.shells.zsh.enable;
    };
    xdg.mimeApps = mkIf cfg.defaultApplication {
      enable = true;
      defaultApplications = {
        "inode/directory" = ["yazi.desktop"];
      };
    };
  };
}
