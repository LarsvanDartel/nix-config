# home.freecad
{...}: {
  den.aspects.home.freecad.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/FreeCAD"
      ".config/FreeCAD"
    ];
    home.packages = with pkgs; [freecad];
  };
}
