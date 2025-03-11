{
  config,
  lib,
  pkgs,
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

    programs.spotify-player.enable = true;
  };
}
