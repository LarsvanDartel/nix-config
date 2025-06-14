{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkPackageOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.gaming.launchers.geforce-now;
in {
  options.modules.gaming.launchers.geforce-now = {
    enable = mkEnableOption "GeForce Now launcher";
    package = mkPackageOption pkgs "gfn-electron" {};
  };
  config = mkIf cfg.enable {
    modules.persist.directories = [".config/GeForce Now"];
    home.packages = [
      cfg.package
    ];
  };
}
