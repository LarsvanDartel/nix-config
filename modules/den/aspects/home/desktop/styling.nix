# home.styling — stylix theming (the _styling tree) + profile font/wallpaper
# values. Delivered by desktop.styling (to-users), which also sets the theme
# and auto-imports the stylix HM module (homeManagerIntegration).
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

      # Same top-ranked file as the picker's default, so scheme and picture
      # can't drift apart.
      wallpaper = {
        src = config.cosmos.desktops.wallpapers.favourite;
        themed = false;
      };
    };
  };
}
