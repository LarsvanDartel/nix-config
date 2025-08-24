{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.gaming.launchers.minecraft;
in {
  options.gaming.launchers.minecraft = {
    enable = mkEnableOption "minecraft launcher";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [".local/share/PrismLauncher"];

    home.packages = with pkgs; [
      (prismlauncher.override {
        gamemodeSupport = true;
      })
    ];
  };
}
