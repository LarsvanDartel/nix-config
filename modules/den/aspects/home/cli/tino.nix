# home.tino — git-remote-tino: `git clone tino::<bucket>` over TINO's REST API
{...}: {
  den.aspects.home.tino.homeManager = {
    config,
    pkgs,
    ...
  }: {
    home.packages = [pkgs.git-remote-tino];

    # Source of truth for the hostname; the helper's built-in default is only a fallback.
    programs.git.settings.tino.url = "https://tino.lvdar.nl";

    # Minted on endeavour (/var/lib/tino/api_keys.yml), where per-bucket committer access is granted.
    sops.secrets."keys/tino/api-key" = {
      sopsFile = "${config.cosmos.security.sops.sopsFolder}/common/secrets.yaml";
      path = "${config.home.homeDirectory}/.config/tino/api-key";
    };
  };
}
