{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.yazi;
in {
  options.cli.programs.yazi = {
    enable = mkEnableOption "yazi file manager";
  };
  config = mkIf cfg.enable {
    cli.shells.zsh.aliases = {
      "y" = "${pkgs.yazi}/bin/yazi";
    };
    programs.yazi = {
      enable = true;
      enableZshIntegration = config.cli.shells.zsh.enable;
    };
  };
}
