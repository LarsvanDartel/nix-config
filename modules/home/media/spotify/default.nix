{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe;

  cfg = config.cosmos.media.spotify;
in {
  options.cosmos.media.spotify = {
    enable = mkEnableOption "spotify";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      ".cache/spotify-player"
    ];

    programs.spotify-player = {
      enable = true;
      package = pkgs.spotify-player;
    };

    xdg.desktopEntries.spotify-player = {
      exec = getExe pkgs.spotify-player;
      name = "Spotify Player";
      terminal = true;
      type = "Application";
    };
  };
}
