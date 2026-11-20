# home.nvim — neovim from launchpad with the fleet theme, wayland clipboard and minuet.
{
  inputs,
  cosmosStyling,
  ...
}: let
  mkNvim = pkgs: settings: let
    monospace = cosmosStyling.font pkgs cosmosStyling.fonts.monospace;
  in
    (inputs.launchpad.lib.mkNvim {
      inherit pkgs;
      modules = [
        {
          launchpad.theme = {
            # Only until home.theme's palette file exists; servers never get one.
            scheme = cosmosStyling.schemeFile cosmosStyling.defaultMode;
            font = {
              inherit (monospace) name;
              size = monospace.recommendedSize;
            };
            opacity = cosmosStyling.opacity.terminal;
          };

          waylandSupport = settings.wayland;

          launchpad.minuet = {
            inherit (settings.minuet) enable;
            # Cross-host literal: den cannot read endeavour's config, so this
            # must track cosmos.services.ollama there.
            endpoint = "http://endeavour.nb.lvdar.nl:11434/v1/completions";
          };
        }
      ];
    }).config.build.package;
in {
  flake-file.inputs.launchpad = {
    # Public HTTPS, not git@knot: keyless builds (spindle CI) have no SSH
    # credential. Run `nix run .#write-flake` after editing.
    url = "git+https://knot.lvdar.nl/did:plc:3l35i5iht5tqeoeqlfxzgkls?shallow=1";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.home.nvim.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption;

    modes = config.cosmos.desktops.common.styling.modes;
    nvim = mkNvim pkgs config.cosmos.cli.programs.nvim;
    palette = mode: let
      colors = (cosmosStyling.colors pkgs mode).withHashtag;
    in
      pkgs.writeText "nvim-palette-${mode}.lua" ''
        return ${lib.generators.toLua {} (lib.getAttrs (map (n: "base0${n}") (lib.stringToCharacters "0123456789ABCDEF")) colors)}
      '';
  in {
    options.cosmos.cli.programs.nvim = {
      wayland = mkEnableOption "wayland clipboard support in nvim";
      minuet.enable = mkEnableOption "LLM completion via minuet against endeavour's ollama";
    };

    config = {
      home = {
        # No language support here: a devshell's launchpad `nvim-<lang>` shadows this on PATH.
        packages = [nvim];
        sessionVariables = {
          EDITOR = "nvim";
          VISUAL = "nvim";
        };
      };

      cosmos.desktops.common.styling.modes = {
        files."nvim-palette.lua" = palette;
        onSwitch = ''
          for s in "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/nvim.*.0; do
            [ -S "$s" ] || continue
            timeout 2 ${lib.getExe nvim} --server "$s" --remote-expr 'execute("LaunchpadThemeReload")' >/dev/null 2>&1 || true
          done
        '';
      };
      xdg.configFile."launchpad/palette.lua" = lib.mkIf modes.enable {
        source = config.lib.file.mkOutOfStoreSymlink "${modes.current}/nvim-palette.lua";
      };
    };
  };
}
