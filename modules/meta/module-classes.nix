# Dendritic aggregation option.
#
# Declares `flake.modules.<class>.<name>` as a merging tree of deferred
# modules, so any number of feature files can each contribute config to a
# named reusable module. `class` is `nixos` or `homeManager`; hosts compose a
# system by importing the features they want from `config.flake.modules.*`.
{
  lib,
  flake-parts-lib,
  ...
}: {
  options.flake = flake-parts-lib.mkSubmoduleOptions {
    modules = lib.mkOption {
      type = with lib.types; lazyAttrsOf (lazyAttrsOf deferredModule);
      default = {};
      description = "Reusable NixOS / home-manager modules, aggregated by feature name.";
      # Attach a stable key to each aggregated feature so that importing the
      # same feature through several paths (diamond imports via profiles)
      # deduplicates instead of declaring its options twice.
      apply = lib.mapAttrs (
        class:
          lib.mapAttrs (
            name: mod: {
              key = "flake.modules.${class}.${name}";
              _file = "flake.modules.${class}.${name}";
              imports = [mod];
            }
          )
      );
    };
  };
}
