# home.winboat — WinBoat Windows apps in a container, over FreeRDP
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
