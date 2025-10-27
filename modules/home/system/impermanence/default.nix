{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.types) listOf str;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.system.impermanence;
in {
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
  ];

  options.cosmos.system.impermanence = {
    enable = mkEnableOption "impermanence";

    persist = {
      files = mkOption {
        type = listOf str;
        default = [];
        description = "List of files to persist";
      };
      directories = mkOption {
        type = listOf str;
        default = [];
        description = "List of directories to persist";
      };
    };
  };

  config = mkIf cfg.enable {
    home.persistence."/persist${config.home.homeDirectory}" = {
      inherit (cfg.persist) files directories;
      allowOther = true;
    };
  };
}
