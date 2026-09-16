# home.spotify (spotify-player)
{...}: {
  den.aspects.home.spotify.homeManager = {
    pkgs,
    lib,
    ...
  }: let
    inherit (lib.meta) getExe;
  in {
    cosmos.system.impermanence.persist.directories = [".cache/spotify-player"];

    programs.spotify-player = {
      enable = true;
      package = pkgs.spotify-player;
    };

    xdg.desktopEntries.spotify-player = {
      exec = getExe pkgs.spotify-player;
      name = "Spotify Player";
      terminal = true;
      type = "Application";
      # Resolved via the icon theme (Nordzy ships spotify-client) to stay
      # consistent with the desktop rather than hardcoding a store path.
      icon = "spotify-client";
      comment = "Terminal Spotify client";
      categories = ["AudioVideo" "Audio" "Music" "Player"];
    };
  };
}
