{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.custom) get-non-default-nix-files;
  inherit (lib.attrsets) listToAttrs attrsToList getAttrs;
  inherit (lib.types) str submodule package int nullOr listOf attrsOf;
  inherit (lib.lists) flatten;
  inherit (lib.options) mkOption;
  inherit (lib.fixedPoints) converge;
  inherit (lib.modules) mkDefault;

  cfg = config.styling.fonts;

  # Font module type
  fontModule = submodule {
    options = {
      name = mkOption {
        type = str;
        description = "Font family name.";
      };
      package = mkOption {
        type = package;
        description = "Font package";
      };
      recommendedSize = mkOption {
        type = nullOr int;
        default = null;
        description = "Recommended size for displaying this font.";
      };
      fallbackFonts = mkOption {
        type = listOf str;
        default = [];
        description = "Fallback fonts for specified font.";
      };
    };
  };

  fontModules = get-non-default-nix-files ./.;

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
  options.styling.fonts = {
    pkgs = mkOption {
      type = attrsOf fontModule;
      default = builtins.listToAttrs (
        map (module: {
          inherit (module) name;
          value = module;
        }) (map (module: (import module) {inherit lib config pkgs;}) fontModules)
      );
      description = "All available fonts";
    };

    installed = mkOption {
      type = listOf str;
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
      type = listOf fontModule;
      default = [];
      description = "Additional fonts to install.";
    };
  };

  config = {
    styling.fonts.fontconfig.enable = true;
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
