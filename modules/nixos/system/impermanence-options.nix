# Impermanence option schema, split out from the activation feature so that any
# feature can contribute persist paths (`cosmos.system.impermanence.persist.*`)
# without pulling in the heavy btrfs-rollback activation. Imported by `common`,
# so the options are declared on every host; the `impermanence` feature reads
# them and only activates where imported.
{...}: {
  flake.modules.nixos.common = {lib, ...}: let
    inherit (lib.types) listOf str coercedTo attrsOf bool;
    inherit (lib.options) mkOption;
  in {
    options.cosmos.system.impermanence = {
      active = mkOption {
        type = bool;
        default = false;
        internal = true;
        description = "Whether root-rollback impermanence is active on this host (set by the impermanence feature).";
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
          example = [
            "/etc/machine-id"
            "/etc/nix/id_rsa"
          ];
          description = ''
            Files that should be stored in persistent storage.
          '';
        };
        directories = mkOption {
          type = listOf (coercedTo str (d: {directory = d;}) (attrsOf str));
          default = [];
          example = [
            "/var/log"
            "/var/lib/bluetooth"
            "/var/lib/nixos"
            "/var/lib/systemd/coredump"
            "/etc/NetworkManager/system-connections"
          ];
          description = ''
            Directories to bind mount to persistent storage.
          '';
        };
      };
    };
  };
}
