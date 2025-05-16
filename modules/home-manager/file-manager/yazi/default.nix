{
  config,
  lib,
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
    programs.yazi = {
      enable = true;
      enableZshIntegration = config.modules.shell.zsh.enable;
    };
  };
}
