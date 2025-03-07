{
  config,
  inputs,
  lib,
  ...
}: let
  cfg = config.modules.persist;
in {
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
  ];

  options.modules.persist = {
    enable = lib.mkEnableOption "impermanence";
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Directories to persist";
    };
  };

  config = lib.mkIf cfg.enable {
    home.persistence."/persist/home/lvdar" = {
      directories = cfg.directories;
      files = [];
      allowOther = true;
    };
  };
}
