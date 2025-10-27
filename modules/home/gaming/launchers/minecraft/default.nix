{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.gaming.launchers.minecraft;
in {
  options.cosmos.gaming.launchers.minecraft = {
    enable = mkEnableOption "minecraft launcher";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".local/share/PrismLauncher"];

    home.packages = with pkgs; [
      (prismlauncher.override {
        gamemodeSupport = true;
      })
    ];
  };
}
