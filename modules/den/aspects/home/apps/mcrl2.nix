# home.mcrl2 — the mCRL2 toolset for the TU/e course
{...}: {
  den.aspects.home.mcrl2.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.mcrl2];
  };
}
