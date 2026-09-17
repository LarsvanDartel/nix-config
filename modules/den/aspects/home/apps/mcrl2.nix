# home.mcrl2 — the mCRL2 toolset: formal specification and analysis of
# concurrent processes (TU/e course tooling, same shelf as
# home.process-mining's ProM/cpn-ide).
{...}: {
  den.aspects.home.mcrl2.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.mcrl2];
  };
}
