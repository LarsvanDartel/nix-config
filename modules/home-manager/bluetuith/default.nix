{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.bluetuith;
in {
  options.modules.bluetuith = {
    enable = lib.mkEnableOption "bluetuith";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [bluetuith];

    xdg.desktopEntries.bluetuith = {
      exec = "${pkgs.bluetuith}/bin/bluetuith";
      name = "Bluetuith";
      terminal = true;
      type = "Application";
    };
  };
}
