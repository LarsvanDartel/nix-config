{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.yazi;
in {
  options.cosmos.cli.programs.yazi = {
    enable = mkEnableOption "yazi file manager";
  };
  config = mkIf cfg.enable {
    cosmos.cli.shells.zsh.aliases = {
      "y" = "${pkgs.yazi}/bin/yazi";
    };
    programs.yazi = {
      enable = true;
      enableZshIntegration = config.cosmos.cli.shells.zsh.enable;
    };
  };
}
