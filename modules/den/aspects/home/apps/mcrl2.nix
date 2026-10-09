# home.mcrl2 — the mCRL2 toolset (TU/e course tooling).
{...}: {
  den.aspects.home.mcrl2.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.mcrl2];
  };
}
