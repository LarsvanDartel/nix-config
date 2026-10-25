# home.nvim — neovim as a standalone nixvim package (`nix run .#nvim`); the
# package holds the config (./_nvim), home-manager only installs it.
{
  inputs,
  cosmosStyling,
  ...
}: let
  # `settings` are ./_nvim/settings.nix values; {} is the server baseline.
  mkNvim = pkgs: settings:
    (inputs.nixvim.lib.evalNixvim {
      modules = [
        ./_nvim
        {
          nixpkgs.pkgs = pkgs;
          cosmos.nvim = settings;
        }
      ];
      extraSpecialArgs = {inherit cosmosStyling;};
    }).config.build.package;
in {
  flake-file.inputs.nixvim = {
    url = "github:nix-community/nixvim";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  perSystem = {pkgs, ...}: {packages.nvim = mkNvim pkgs {};};

  den.aspects.home.nvim.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.cosmos.cli.programs.nvim = lib.mkOption {
      type = lib.types.submodule ./_nvim/settings.nix;
      default = {};
      description = "Per-host additions baked into this user's nvim package.";
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
