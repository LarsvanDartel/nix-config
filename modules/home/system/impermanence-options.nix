# Home-side impermanence option schema (persist paths are home-relative).
# Split from the activation feature so any home feature can contribute persist
# paths without pulling in the activation. Imported by home `common`.
{...}: {
  flake.modules.homeManager.common = {lib, ...}: let
    inherit (lib.types) listOf str coercedTo attrsOf bool;
    inherit (lib.options) mkOption;
  in {
    options.cosmos.system.impermanence = {
      active = mkOption {
        type = bool;
        default = false;
        internal = true;
        description = "Whether home impermanence is active on this host (set by the impermanence feature).";
      };

      persist = {
        files = mkOption {
          type = listOf (coercedTo str (f: {file = f;}) (attrsOf str));
          default = [];
          description = ''
            Files that should be stored in persistent storage.
          '';
        };
        directories = mkOption {
          type = listOf (coercedTo str (d: {directory = d;}) (attrsOf str));
          default = [];
          description = ''
            Directories to bind mount to persistent storage.
          '';
        };
      };
    };
  };
}
