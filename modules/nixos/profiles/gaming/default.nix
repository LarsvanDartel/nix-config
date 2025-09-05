{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.profiles.gaming;
in {
  options.profiles.gaming = {
    enable = mkEnableOption "gaming configuration";
  };
  config = mkIf cfg.enable {
    profiles = {
      common.enable = true;
      desktop.enable = true;
    };

    # TODO: move to dedicated steam module
    programs.steam = {
      enable = true;
      extraPackages = with pkgs; [
        proton-ge-bin
      ];
    };

    programs.gamemode.enable = true;
  };
}
