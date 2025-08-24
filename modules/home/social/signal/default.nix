{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.social.signal;
in {
  options.social.signal = {
    enable = mkEnableOption "signal";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [
      ".config/Signal"
    ];

    home.packages = with pkgs; [
      signal-desktop
    ];
  };
}
