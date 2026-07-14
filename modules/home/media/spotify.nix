{...}: {
  flake.modules.homeManager.desktop = {
    pkgs,
    lib,
    ...
  }: let
    inherit (lib.meta) getExe;
  in {
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
