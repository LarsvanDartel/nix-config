# Host configurations as data. Each `configurations.<name>` is a submodule
# holding a `system` and a `module`; its `evaluation` (a nixosSystem) is derived
# read-only. pkgs is taken from the matching perSystem via `withSystem`, so it
# is built once per system and shared across hosts. Each host also produces a
# `flake.checks.<system>.nixos-<name>` build check.
{
  lib,
  config,
  inputs,
  withSystem,
  ...
}: let
  inherit (lib) types mkOption mapAttrs mapAttrsToList mkMerge;
in {
  options.configurations = mkOption {
    default = {};
    description = "NixOS host configurations, assembled into flake.nixosConfigurations.";
    type = types.lazyAttrsOf (
      types.submodule (
        {
          name,
          config,
          ...
        }: {
          options = {
            system = mkOption {
              type = types.str;
              description = "System double the host is built for.";
            };
            module = mkOption {
              type = types.deferredModule;
              description = "The host's top-level NixOS module.";
            };
            evaluation = mkOption {
              readOnly = true;
              type = types.raw;
              default = inputs.nixpkgs.lib.nixosSystem {
                specialArgs = {inherit inputs;};
                modules = [
                  config.module
                  ({lib, ...}: {
                    networking.hostName = lib.mkDefault name;
                    nixpkgs.pkgs = withSystem config.system ({pkgs, ...}: pkgs);
                  })
                ];
              };
            };
          };
        }
      )
    );
  };

  config.flake.nixosConfigurations = mapAttrs (_: c: c.evaluation) config.configurations;

  config.flake.checks = mkMerge (
    mapAttrsToList (name: c: {
      ${c.system}."nixos-${name}" = c.evaluation.config.system.build.toplevel;
    })
    config.configurations
  );
}
