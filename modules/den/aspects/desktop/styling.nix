# desktop.styling — system stylix + every user's home.styling (to-users), and
# the `cosmosStyling` module arg: the scheme, opacity and fonts as plain data.
# Wrapped programs read that arg because their config is the source of truth,
# so no stylix target reaches them; stylix reads the same values, so the
# two can't drift. Not read from the home user's stylix (that would be a
# home→nixos cross-eval).
{
  den,
  inputs,
  lib,
  ...
}: let
  scheme = "nord";
  darkMode = true;
  # The flake input, not pkgs.base16-schemes (same tinted-theming files): the
  # palette is read at eval time, and a package path would make that IFD.
  schemeFile = "${inputs.stylix.inputs.tinted-schemes}/base16/${scheme}${lib.optionalString (!darkMode) "-light"}.yaml";

  fontsDir = ../home/desktop/_styling/fonts;
  fontFiles = lib.attrNames (lib.filterAttrs (n: t: t == "regular" && n != "default.nix" && lib.hasSuffix ".nix" n) (builtins.readDir fontsDir));
in {
  flake-file.inputs.stylix = {
    url = "github:nix-community/stylix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  _module.args.cosmosStyling = {
    inherit scheme darkMode schemeFile;
    # Load-bearing: `terminal` also flips btop's/helix's `transparent`, or a
    # TUI paints an opaque rectangle through the terminal. noctalia reads these
    # by hand (_noctalia/home.nix). `applications` stays 1.0 deliberately.
    opacity = {
      terminal = 0.8;
      desktop = 0.8;
      popups = 0.8;
      applications = 1.0;
    };
    # Family names from home/desktop/_styling/fonts; resolve with `font`.
    fonts = {
      serif = "DejaVu Serif";
      sansSerif = "DejaVu Sans";
      # The vector cut: identical at 13px, and still crisp at 26, 39… when zoomed.
      monospace = "Cozette Vector";
      emoji = "Noto Color Emoji";
      interface = "Cozette Vector";
    };
    # base16.nix scheme attrs: the same value as stylix's config.lib.stylix.colors.
    colors = pkgs: (inputs.stylix.inputs.base16.lib {inherit pkgs lib;}).mkSchemeAttrs schemeFile;
    font = pkgs: name:
      lib.findFirst (f: f.name == name) (throw "cosmosStyling: no font file named ${name}")
      (map (f: import (fontsDir + "/${f}") {inherit pkgs lib;}) fontFiles);
  };

  den.aspects.desktop.styling = {
    provides.to-users = {
      includes = [den.aspects.home.styling];
      homeManager.cosmos.desktops.common.styling.theme = {
        ${scheme} = {
          enable = true;
          inherit darkMode;
        };
        colorScheme = schemeFile;
      };
    };

    nixos = {
      imports = [inputs.stylix.nixosModules.stylix];

      stylix = {
        enable = true;
        base16Scheme = schemeFile;
        homeManagerIntegration = {
          followSystem = false;
          autoImport = true;
        };
      };
    };
  };
}
