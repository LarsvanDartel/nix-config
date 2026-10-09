# home.kanidm — the kanidm CLI. Pinned to _1_11 to match services/kanidm.nix's
# server (versioned protocol).
{...}: {
  den.aspects.home.kanidm.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.kanidm_1_11];

    xdg.configFile."kanidm/config".text = ''
      uri = "https://auth.lvdar.nl"
    '';
  };
}
