# home.tino — git-remote-tino (pkgs/git-remote-tino.nix): `git clone tino::<bucket>`
# over TINO's public REST API. The API key is minted on endeavour
# (/var/lib/tino/api_keys.yml); committer access per bucket is granted there.
{...}: {
  den.aspects.home.tino.homeManager = {
    config,
    pkgs,
    ...
  }: {
    home.packages = [pkgs.git-remote-tino];

    # Source of truth for the hostname; the helper's built-in default is only a fallback.
    programs.git.settings.tino.url = "https://tino.lvdar.nl";

    sops.secrets."keys/tino/api-key" = {
      sopsFile = "${config.cosmos.security.sops.sopsFolder}/common/secrets.yaml";
      path = "${config.home.homeDirectory}/.config/tino/api-key";
    };
  };
}
