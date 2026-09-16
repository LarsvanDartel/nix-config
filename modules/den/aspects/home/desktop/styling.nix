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
        # Without enable, stylix silently falls back to DejaVu Sans Mono
        # everywhere and Cozette is never installed (long-standing latent bug).
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

      # Same file the picker gets as its default, from the same `wallpapers`
      # input, so scheme and picture cannot drift apart; takes the ranking's
      # top image, overriding the module's own (different) default. `themed`
      # (gowall onto base16) is off: this is a photograph shown by hyprpaper,
      # hyprlock and the greeter, and recolouring it is very visible.
      wallpaper = {
        src = config.cosmos.desktops.wallpapers.favourite;
        themed = false;
      };
    };
  };
}
