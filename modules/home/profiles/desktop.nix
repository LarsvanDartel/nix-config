# Profile-level config for the home `desktop` aggregate (styling, firefox,
# foot, media, social apps self-register into it from their own files).
{...}: {
  flake.modules.homeManager.desktop = {
    config,
    pkgs,
    ...
  }: {
    cosmos.cli.programs.nvim.wayland = true;

    cosmos.desktops.common.styling = {
      fonts = let
        fontpkgs = config.cosmos.desktops.common.styling.fonts.pkgs;
      in {
        serif = fontpkgs."DejaVu Serif";
        sansSerif = fontpkgs."DejaVu Sans";
        monospace = fontpkgs."Cozette";
        emoji = fontpkgs."Noto Color Emoji";
        interface = fontpkgs."Cozette";
        extraFonts = [];
      };

      theme.nord = {
        enable = true;
        darkMode = true;
      };

      wallpaper = {
        src = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/dharmx/walls/6bf4d733ebf2b484a37c17d742eb47e5139e6a14/digital/a_group_of_birds_flying_in_the_sky.jpg";
          hash = "sha256-v6KVInk5JJZPLkOAfC8yuDQtnZtT1DWQI7u6UfG59WY=";
        };
        themed = true;
      };
    };
  };
}
