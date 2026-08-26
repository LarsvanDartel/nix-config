# home.styling — stylix theming (reuses the styling _impl tree) + the profile
# font/theme/wallpaper values (was home/profiles/desktop.nix). The stylix HM
# module is auto-imported by the nixos desktop styling (homeManagerIntegration).
{...}: {
  den.aspects.home.styling.homeManager = {
    config,
    inputs,
    ...
  }: {
    imports = [./_styling];

    cosmos.desktops.common.styling = {
      fonts = let
        fontpkgs = config.cosmos.desktops.common.styling.fonts.pkgs;
      in {
        # Turn on the font feature so the configured fonts (Cozette monospace/
        # interface, DejaVu serif/sans, Noto emoji) actually install and drive
        # stylix.fonts. Without this, stylix silently falls back to DejaVu Sans
        # Mono everywhere and Cozette is never installed (long-standing latent bug).
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

      # The image the whole scheme is generated from, and also the background
      # `home.wallpapers` hands the picker as its default — the same file, out
      # of the same `wallpapers` input, so the desktop's colours and the picture
      # they came from cannot drift apart.
      #
      # This overrides the module's own default, which is why that default
      # being a different image never showed up anywhere.
      wallpaper = {
        src = "${inputs.wallpapers}/defaults/birds-in-the-sky.jpg";
        themed = true;
      };
    };
  };
}
