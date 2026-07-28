# home.orca-slicer
{...}: {
  den.aspects.home.orca-slicer.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [
      ".config/OrcaSlicer"
      ".local/share/orca-slicer"
    ];
    home.packages = with pkgs; [orca-slicer];
  };
}
