# home.kanidm — the kanidm CLI for account/group admin without the web
# UI. Pinned to _1_11 to match services/kanidm.nix's server package —
# the CLI and server speak a versioned protocol.
{...}: {
  den.aspects.home.kanidm.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.kanidm_1_11];

    # Public endpoint by default so `kanidm ...` needs no flags.
    # verify_ca is fine — auth.lvdar.nl is a normal ACME cert via
    # gaia's netbird-proxy, not kanidm's self-signed one.
    xdg.configFile."kanidm/config".text = ''
      uri = "https://auth.lvdar.nl"
    '';
  };
}
