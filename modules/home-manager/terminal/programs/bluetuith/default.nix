{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.terminal.programs.bluetuith;
in {
  options.modules.terminal.programs.bluetuith = {
    enable = mkEnableOption "bluetuith";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [bluetuith];

    xdg.desktopEntries.bluetuith = {
      exec = "${pkgs.bluetuith}/bin/bluetuith";
      name = "Bluetuith";
      terminal = true;
      type = "Application";
    };
  };
}
