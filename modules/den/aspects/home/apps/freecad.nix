# home.freecad — FreeCAD parametric CAD
{...}: {
  den.aspects.home.freecad.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/FreeCAD"
      ".config/FreeCAD"
    ];
    home.packages = with pkgs; [freecad];
  };
}
