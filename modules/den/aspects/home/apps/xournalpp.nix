# home.xournalpp — handwritten notes and PDF annotation with the stylus.
{...}: {
  den.aspects.home.xournalpp.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.xournalpp];
    cosmos.system.impermanence.persist.directories = [".config/xournalpp"];
  };
}
