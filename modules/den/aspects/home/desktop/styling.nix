# home.styling — stylix theming (the _styling tree) + profile font/theme/
# wallpaper values. The stylix HM module is auto-imported by the nixos
# desktop styling (homeManagerIntegration).
{...}: {
  den.aspects.home.styling.homeManager = {config, ...}: {
    imports = [./_styling];

    cosmos.desktops.common.styling = {
      fonts = let
        fontpkgs = config.cosmos.desktops.common.styling.fonts.pkgs;
      in {
        # Without enable, stylix silently falls back to DejaVu Sans Mono.
        enable = true;

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

      # Same top-ranked file as the picker's default, so scheme and picture
      # can't drift apart.
      wallpaper = {
        src = config.cosmos.desktops.wallpapers.favourite;
        themed = false;
      };
    };
  };
}
