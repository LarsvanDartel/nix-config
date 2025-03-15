{
  config,
  lib,
  ...
}: let
  cfg = config.modules.spotify;
in {
  options.modules.spotify = {
    enable = lib.mkEnableOption "spotify";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      ".cache/spotify-player"
    ];
    modules.graphical.startupCommands = lib.mkOrder 800 [
      "${config.modules.terminal.default} --title \"Spotify Player\" -e spotify_player"
    ];

    programs.spotify-player.enable = true;
  };
}
