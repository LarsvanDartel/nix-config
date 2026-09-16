# core.impermanence-options — persist option schema, declared on every host so
# any aspect can contribute persist paths; the `impermanence` aspect reads them
# and only activates where included. Also declares cosmos.user.name (ssh/sops).
{...}: {
  den.aspects.core.impermanence-options.nixos = {lib, ...}: let
    inherit (lib.types) listOf str coercedTo attrsOf bool;
    inherit (lib.options) mkOption;
  in {
    options.cosmos.user.name = mkOption {
      type = str;
      default = "lvdar";
      description = "Username of the main user (host-level; matches the den user entity).";
    };

    options.cosmos.system.impermanence = {
      active = mkOption {
        type = bool;
        default = false;
        internal = true;
        description = "Whether root-rollback impermanence is active on this host.";
      };
      device = mkOption {
        type = str;
        default = "/dev/mapper/crypted";
        description = "The device the root filesystem is located on";
      };
      persist = {
        files = mkOption {
          type = listOf (coercedTo str (f: {file = f;}) (attrsOf str));
          default = [];
          description = "Files that should be stored in persistent storage.";
        };
        directories = mkOption {
          type = listOf (coercedTo str (d: {directory = d;}) (attrsOf str));
          default = [];
          description = "Directories to bind mount to persistent storage.";
        };
      };
    };
  };
}
