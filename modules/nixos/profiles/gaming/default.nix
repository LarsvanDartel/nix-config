{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.profiles.gaming;
in {
  options.cosmos.profiles.gaming = {
    enable = mkEnableOption "gaming configuration";
  };
  config = mkIf cfg.enable {
    cosmos = {
      profiles = {
        common.enable = true;
        desktop.enable = true;
      };
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
