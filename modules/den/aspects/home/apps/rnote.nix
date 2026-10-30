# home.rnote — vector sketching and notes with the stylus.
{...}: {
  den.aspects.home.rnote.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.rnote];
    # Rnote keeps its settings in GSettings; nothing else persisted dconf, so this keeps every GSettings app's settings.
    cosmos.system.impermanence.persist.directories = [".config/dconf"];
  };
}
