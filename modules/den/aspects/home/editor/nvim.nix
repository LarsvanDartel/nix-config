# home.nvim — neovim from launchpad (lvdar's nvim + devshell flake) with the
# fleet's theme, wayland clipboard and minuet layered on. Language support is
# not installed here: a project's devshell brings launchpad's matching
# `nvim-<lang>` variant, which shadows this one on PATH.
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
            scheme = cosmosStyling.schemeFile;
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
    # Public HTTPS, not git@knot: hosts building via build-gate have no SSH
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
  in {
    options.cosmos.cli.programs.nvim = {
      wayland = mkEnableOption "wayland clipboard support in nvim";
      # Needs endeavour's ollama on the mesh.
      minuet.enable = mkEnableOption "LLM completion via minuet against endeavour's ollama";
    };

    config.home = {
      packages = [(mkNvim pkgs config.cosmos.cli.programs.nvim)];
      sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };
    };
  };
}
