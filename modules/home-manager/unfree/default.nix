{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.unfree;
in {
  options.modules.unfree = {
    enable = lib.mkEnableOption "unfree";
    allowedPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config = {
      allowUnfree = true;
      allowUnreePredicate = pkg:
        builtins.elem (lib.getName pkg) cfg.allowedPackages;
    };
  };
}
