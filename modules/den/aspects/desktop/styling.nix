# desktop.styling — system stylix + every user's home.styling and home.theme
# (to-users), and the `cosmosStyling` module arg: the theme's dark and light
# schemes, opacity and fonts as plain data. Wrapped programs read that arg
# because their config is the source of truth, so no stylix target reaches
# them; stylix reads the same values, so the two can't drift. Not read from
# the home user's stylix (that would be a home→nixos cross-eval).
{
  den,
  inputs,
  lib,
  ...
}: let
  # Each theme names its tinted-theming scheme per mode, its icon theme
  # (home/desktop/_styling/icons) and its accent: the base16 slot for
  # noctalia's primary and the focused-window colour in niri and Umbriel.
  # Switching theme is this one word.
  themes = {
    # Not everforest-dark-medium: same background, but its base05 is the
    # grey 859289, too dim for body text.
    everforest = {
      dark = "everforest";
      light = "everforest-light-medium";
      icons = "everforest";
      # Its green; stylix's noctalia target would take base0D, a blue.
      accent = "base0B";
    };
    nord = {
      dark = "nord";
      light = "nord-light";
      icons = "nordzy";
      accent = "base0D";
    };
  };
  theme = "everforest";
  # What the system (greeter, console, plymouth, niri's fallback colours) and
  # a fresh home start in; `theme light|dark` switches the session at runtime.
  defaultMode = "dark";
  modes = ["dark" "light"];

  # The flake input, not pkgs.base16-schemes (same tinted-theming files): the
  # palette is read at eval time, and a package path would make that IFD.
  schemeFile = mode: "${inputs.stylix.inputs.tinted-schemes}/base16/${themes.${theme}.${mode}}.yaml";

  fontsDir = ../home/desktop/_styling/fonts;
  fontFiles = lib.attrNames (lib.filterAttrs (n: t: t == "regular" && n != "default.nix" && lib.hasSuffix ".nix" n) (builtins.readDir fontsDir));

  # The runtime mode lives in this link (relative to $HOME): `current` points
  # at `dark` or `light`, each a link to that mode's file farm (home.theme).
  stateDir = ".local/state/cosmos/theme";
in {
  flake-file.inputs.stylix = {
    url = "github:nix-community/stylix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  _module.args.cosmosStyling = {
    inherit theme defaultMode modes schemeFile stateDir;
    iconTheme = themes.${theme}.icons;
    inherit (themes.${theme}) accent;
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
    # base16.nix scheme attrs for a mode: the same value as stylix's
    # config.lib.stylix.colors under that scheme.
    colors = pkgs: mode: (inputs.stylix.inputs.base16.lib {inherit pkgs lib;}).mkSchemeAttrs (schemeFile mode);
    # Raw files skip the fontModule submodule: fill in its defaults.
    font = pkgs: name:
      lib.findFirst (f: f.name == name) (throw "cosmosStyling: no font file named ${name}")
      (map (f:
        {
          recommendedSize = null;
          pixelGrid = null;
          boldFamily = null;
          fallbackFonts = [];
        }
        // import (fontsDir + "/${f}") {inherit pkgs lib;})
      fontFiles);

    # A program whose config bakes in colours, built once per mode: every
    # bin/ entry execs the variant matching the runtime mode, so a new launch
    # follows `theme`. Everything else (share/, desktop files) is the default
    # mode's. `mk` takes the mode.
    modal = pkgs: name: mk: let
      variants = lib.genAttrs modes mk;
      default = variants.${defaultMode};
      dispatch = pkgs.runCommand "${name}-modal-bin" {} ''
        mkdir -p $out/bin
        for bin in ${default}/bin/*; do
          bin=$(basename "$bin")
          cat >"$out/bin/$bin" <<EOF
        #!${pkgs.runtimeShell}
        case "\$(readlink "\$HOME/${stateDir}/current" 2>/dev/null)" in
        ${lib.concatMapStrings (mode: ''
            ${mode}) exec ${variants.${mode}}/bin/$bin "\$@" ;;
          '')
          modes}esac
        exec ${default}/bin/$bin "\$@"
        EOF
          chmod +x "$out/bin/$bin"
        done
      '';
    in
      pkgs.symlinkJoin {
        name = "${name}-modal";
        paths = [dispatch default];
        passthru = {inherit variants;};
      };
  };

  den.aspects.desktop.styling = {
    provides.to-users.includes = [den.aspects.home.styling den.aspects.home.theme];

    nixos = {
      imports = [inputs.stylix.nixosModules.stylix];

      stylix = {
        enable = true;
        base16Scheme = schemeFile defaultMode;
        polarity = defaultMode;
        homeManagerIntegration = {
          followSystem = false;
          autoImport = true;
        };
      };
    };
  };
}
