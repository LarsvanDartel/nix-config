# home.kanidm — the kanidm CLI. Pinned to _1_12 to match services/kanidm.nix's
# server (versioned protocol).
{...}: {
  den.aspects.home.kanidm.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.kanidm_1_12];

    # The CLI reads ~/.config/kanidm itself as the file, not a directory.
    xdg.configFile.kanidm.text = ''
      uri = "https://auth.lvdar.nl"
    '';
  };
}
