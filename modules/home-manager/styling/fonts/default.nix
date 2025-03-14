{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.styling.fonts;

  # Font module type
  fontModule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Font family name.";
      };
      package = mkOption {
        type = types.package;
        description = "Font package";
      };
      recommendedSize = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Recommended size for displaying this font.";
      };
      fallbackFonts = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Fallback fonts for specified font.";
      };
    };
  };

  fontModules = [
    # Import all fonts
    ./cozette-vector.nix
    ./cozette.nix
    ./dejavu-sans.nix
    ./dejavu-serif.nix
    # ./fira-code.nix
    ./symbols-nerd-font.nix
    ./noto-color-emoji.nix
  ];

  # Gather enabled fonts.
  enabledFonts =
    [
      cfg.serif.name
      cfg.sansSerif.name
      cfg.monospace.name
      cfg.emoji.name
    ]
    ++ map (font: font.name) cfg.extraFonts;

  # Flatten dependencies of fonts
  fontPackages =
    converge
    (
      fonts:
        listToAttrs (
          map
          (font: {
            name = font;
            value = true;
          })
          (
            flatten (map (font: [font.name] ++ cfg.pkgs.${font.name}.fallbackFonts) (attrsToList fonts))
          )
        )
    )
    (
      listToAttrs (
        map (font: {
          name = font;
          value = true;
        })
        enabledFonts
      )
    );

  # Convert set of fonts to list of packages
  fontNameList = map (font: font.name) (attrsToList fontPackages);
  fontPackageList = map (font: cfg.pkgs.${font}.package) fontNameList;
in {
  imports = [
    ./fontconfig.nix
  ];

  options.modules.styling.fonts = {
    pkgs = mkOption {
      type = types.attrsOf fontModule;
      default = builtins.listToAttrs (
        map (module: {
          inherit (module) name;
          value = module;
        }) (map (module: (import module) {inherit lib config pkgs;}) fontModules)
      );
      description = "All available font modules.";
    };

    installed = mkOption {
      type = types.listOf types.str;
      default = fontNameList;
      description = "List of installed fonts.";
    };

    serif = mkOption {
      type = fontModule;
      description = "Default serif font";
    };

    sansSerif = mkOption {
      type = fontModule;
      description = "Default sansSerif font.";
    };

    monospace = mkOption {
      type = fontModule;
      description = "Default monospace font.";
    };

    emoji = mkOption {
      type = fontModule;
      description = "Default emoji font.";
    };

    interface = mkOption {
      type = fontModule;
      description = "Default interface font.";
    };

    extraFonts = mkOption {
      type = types.listOf fontModule;
      default = [];
      description = "Additional fonts to install.";
    };
  };

  config = {
    modules.styling.fonts.fontconfig.enable = true;
    home.packages = fontPackageList;

    stylix.fonts = {
      serif = getAttrs ["name" "package"] cfg.serif;
      sansSerif = getAttrs ["name" "package"] cfg.sansSerif;
      monospace = getAttrs ["name" "package"] cfg.monospace;
      emoji = getAttrs ["name" "package"] cfg.emoji;

      sizes = {
        applications = mkDefault cfg.serif.recommendedSize;
        desktop = mkDefault cfg.interface.recommendedSize;
        popups = mkDefault cfg.interface.recommendedSize;
        terminal = mkDefault cfg.monospace.recommendedSize;
      };
    };
  };
}
