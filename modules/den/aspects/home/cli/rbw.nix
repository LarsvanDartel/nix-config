# home.rbw — Bitwarden CLI against the vaultwarden on endeavour (services/vaultwarden.nix)
{den, ...}: {
  den.aspects.home.rbw = {
    # gnome-keyring's prompter is what makes pinentry-gnome3 work outside GNOME.
    includes = [den.aspects.home.keyring];

    homeManager = {pkgs, ...}: {
      programs.rbw = {
        enable = true;
        settings = {
          base_url = "https://vault.lvdar.nl";
          email = "lars@lvdar.nl";
          # vaultwarden is SSO_ONLY and ignores the identifier's value, but rbw
          # only takes the SSO path when one is set.
          sso_id = "lvdar.nl";
          pinentry = pkgs.pinentry-gnome3;
        };
      };

      cosmos.system.impermanence.persist.directories = [
        ".local/share/rbw"
        ".cache/rbw"
      ];
    };
  };
}
