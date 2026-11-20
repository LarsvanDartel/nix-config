# home.styling — stylix theming in the default mode, from cosmosStyling; see docs/src/theming.md.
{cosmosStyling, ...}: {
  den.aspects.home.styling.homeManager = {
    config,
    lib,
    ...
  }: let
    dark = config.stylix.polarity == "dark";
  in {
    imports = [./_styling];

    stylix = {
      base16Scheme = cosmosStyling.schemeFile cosmosStyling.defaultMode;
      polarity = cosmosStyling.defaultMode;
      opacity = {inherit (cosmosStyling.opacity) terminal desktop popups;};

      targets = {
        # Its target sets the renamed programs.rofi.font, which abort-on-warn fails.
        rofi.enable = false;
        # They undo the mode at every activation; see docs/src/theming.md#pitfalls.
        gnome.enable = false;
        kde.enable = false;
        # Its ~/.themes copy is named per mode, which a link can't switch.
        gtk.flatpakSupport.enable = false;
      };
    };

    # stylix keeps adw-gtk3 for both modes; naming the variant per mode lets `theme`
    # flip running GTK3 apps live through gtk-theme.
    gtk.theme.name = lib.mkForce (
      if dark
      then "adw-gtk3-dark"
      else "adw-gtk3"
    );

    cosmos.desktops.common.styling = {
      icons.theme = cosmosStyling.iconTheme;

      fonts = let
        fontpkgs = config.cosmos.desktops.common.styling.fonts.pkgs;
      in
        {
          # Without enable, stylix silently falls back to DejaVu Sans Mono.
          enable = true;
          extraFonts = [fontpkgs."Tiny5 Mono" fontpkgs."Atkinson Hyperlegible Mono"];
        }
        // builtins.mapAttrs (_: name: fontpkgs.${name}) cosmosStyling.fonts;

      # Same file as the picker's default, so scheme and picture can't drift apart.
      wallpaper = {
        src = config.cosmos.desktops.wallpapers.favourite;
        themed = false;
      };
    };
  };
}
