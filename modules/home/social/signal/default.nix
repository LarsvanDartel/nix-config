{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.social.signal;
in {
  options.cosmos.social.signal = {
    enable = mkEnableOption "signal";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      ".config/Signal"
    ];

    home.packages = with pkgs; [
      signal-desktop
    ];
  };
}
