# home.styling — stylix theming (the _styling tree) in the default mode, plus
# profile font/wallpaper values. Delivered by desktop.styling (to-users),
# which also auto-imports the stylix HM module (homeManagerIntegration).
# Scheme, fonts and opacity come from cosmosStyling, which wrapped programs
# read too; home.theme renders the other mode and switches at runtime.
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
        # No rofi in the fleet, and its target still sets the renamed
        # programs.rofi.font, which abort-on-warn turns into a build failure.
        rofi.enable = false;
        # GNOME/Plasma integration: on niri they only rewrite dconf's
        # color-scheme (and kdeglobals) at every activation, fighting `theme`.
        gnome.enable = false;
        kde.enable = false;
        # No flatpaks; its ~/.themes copy would be named per mode.
        gtk.flatpakSupport.enable = false;
      };
    };

    # stylix keeps adw-gtk3 (light) and paints dark through gtk.css. Naming
    # the variant per mode lets `theme` flip running GTK3 apps live through
    # gtk-theme; the colours follow on their next start.
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
          extraFonts = [];
        }
        // builtins.mapAttrs (_: name: fontpkgs.${name}) cosmosStyling.fonts;

      # Same top-ranked file as the picker's default, so scheme and picture
      # can't drift apart.
      wallpaper = {
        src = config.cosmos.desktops.wallpapers.favourite;
        themed = false;
      };
    };
  };
}
