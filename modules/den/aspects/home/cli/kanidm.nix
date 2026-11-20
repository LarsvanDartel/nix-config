# home.kanidm — the kanidm CLI
{...}: {
  den.aspects.home.kanidm.homeManager = {pkgs, ...}: {
    # Hand-synced with services/kanidm.nix's server version: the protocol is versioned.
    home.packages = [pkgs.kanidm_1_12];

    # The CLI reads ~/.config/kanidm itself as the file, not a directory.
    xdg.configFile.kanidm.text = ''
      uri = "https://auth.lvdar.nl"
    '';
  };
}
