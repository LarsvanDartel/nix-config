{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.file-manager.yazi;
in {
  options.modules.file-manager.yazi = {
    enable = mkEnableOption "yazi file manager";
  };
  config = mkIf cfg.enable {
    modules.terminal.shell.aliases = {
      "y" = "${pkgs.yazi}/bin/yazi";
    };
    programs.yazi = {
      enable = true;
      enableZshIntegration = config.modules.terminal.shell.zsh.enable;
    };
  };
}
