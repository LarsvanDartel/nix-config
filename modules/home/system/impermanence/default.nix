{
  config,
  lib,
  ...
}: let
  inherit (lib.types) listOf str coercedTo attrsOf;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.system.impermanence;
in {
  options.cosmos.system.impermanence = {
    enable = mkEnableOption "impermanence";

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

  config = mkIf cfg.enable {
    home.persistence."/persist" = {
      inherit (cfg.persist) files directories;
    };
  };
}
