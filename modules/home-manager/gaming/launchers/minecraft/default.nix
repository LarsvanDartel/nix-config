{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.gaming.launchers.minecraft;
in {
  options.modules.gaming.launchers.minecraft = {
    enable = mkEnableOption "minecraft launcher";
  };

  config = mkIf cfg.enable {
    modules.persist.directories = [".local/share/PrismLauncher"];
    home.packages = with pkgs; [
      (prismlauncher.override {
        gamemodeSupport = true;
      })
    ];
  };
}
