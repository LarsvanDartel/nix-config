{...}: {
  flake.modules.homeManager.freecad = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/FreeCAD"
      ".config/FreeCAD"
    ];

    home.packages = with pkgs; [freecad];
  };
}
