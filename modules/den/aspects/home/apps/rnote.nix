# home.rnote — vector sketching and notes with the stylus
{...}: {
  den.aspects.home.rnote.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.rnote];
    # The only dconf persist entry: it keeps every GSettings app's settings, not just Rnote's.
    cosmos.system.impermanence.persist.directories = [".config/dconf"];
  };
}
