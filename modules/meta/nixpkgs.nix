# nixpkgs instance + the `nixpkgs.overlays` aggregation option. The pkgs set
# is built once per system here and shared to hosts via withSystem
# (configurations.nix); local packages self-register from modules/pkgs/*.nix.
{
  inputs,
  lib,
  config,
  ...
}: {
  options.nixpkgs.overlays = lib.mkOption {
    type = lib.types.listOf lib.types.raw;
    default = [];
    description = "Overlays applied to the shared per-system pkgs (features append to this).";
  };

  config.perSystem = {system, ...}: let
    stable = final: _prev: {
      stable = import inputs.nixpkgs-stable {
        inherit (final) system;
        config.allowUnfree = true;
      };
    };

    unstable = final: _prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final) system;
        config.allowUnfree = true;
      };
    };

    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays =
        config.nixpkgs.overlays
        ++ [
          stable
          unstable
          inputs.nur.overlays.default
        ];
      config.allowUnfree = true;
    };
  in {
    _module.args.pkgs = pkgs;
  };
}
