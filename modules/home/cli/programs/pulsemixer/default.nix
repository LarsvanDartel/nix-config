{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.pulsemixer;
in {
  options.cosmos.cli.programs.pulsemixer = {
    enable = mkEnableOption "pulsemixer";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [pulsemixer];

    xdg.desktopEntries.pulsemixer = {
      name = "Pulsemixer";
      comment = "Pulsemixer is a simple ncurses mixer for PulseAudio";
      exec = "${pkgs.pulsemixer}/bin/pulsemixer";
      terminal = true;
      categories = ["AudioVideo" "Audio"];
    };
  };
}
