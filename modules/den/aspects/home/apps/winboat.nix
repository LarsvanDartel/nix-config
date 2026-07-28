# home.winboat
{...}: {
  den.aspects.home.winboat.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.freerdp pkgs.winboat];
    cosmos.system.impermanence.persist.directories = [
      "winboat"
      ".winboat"
      ".config/winboat"
      ".local/share/containers"
    ];
  };
}
