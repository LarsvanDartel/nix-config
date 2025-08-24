{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.media.spotify;
in {
  options.media.spotify = {
    enable = mkEnableOption "spotify";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [
      ".cache/spotify-player"
    ];

    programs.spotify-player.enable = true;

    xdg.desktopEntries.spotify-player = {
      exec = "${pkgs.spotify-player}/bin/spotify_player";
      name = "Spotify Player";
      terminal = true;
      type = "Application";
    };
  };
}
