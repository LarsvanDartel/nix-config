# home.* — small single-package desktop apps (freecad, orca-slicer, simplelogin,
# pangolin-cli, zotero is separate, winboat).
{...}: {
  den.aspects.home.freecad.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/FreeCAD"
      ".config/FreeCAD"
    ];
    home.packages = with pkgs; [freecad];
  };

  den.aspects.home.orca-slicer.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [
      ".config/OrcaSlicer"
      ".local/share/orca-slicer"
    ];
    home.packages = with pkgs; [orca-slicer];
  };

  den.aspects.home.simplelogin.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/simplelogin-cli"];
    home.packages = [pkgs.simplelogin-cli];
  };

  den.aspects.home.pangolin.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/pangolin"];
    home.packages = [pkgs.pangolin-cli];
  };

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
