{...}: {
  flake.modules.homeManager.winboat = {pkgs, ...}: {
    home.packages = [
      pkgs.freerdp
      pkgs.winboat
    ];

    cosmos.system.impermanence.persist.directories = [
      "winboat"
      ".winboat"
      ".config/winboat"
      ".local/share/containers"
    ];
  };
}
