{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.signal;
in {
  options.modules.signal = {
    enable = lib.mkEnableOption "signal";
    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Autostart signal";
    };
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      ".config/Signal"
    ];
    modules.graphical.startupCommands =
      lib.mkIf cfg.autostart
      (lib.mkOrder 801 (
        let
          signal = "${pkgs.signal-desktop}/bin/signal-desktop";
        in ["${signal} & sleep 1 && ${signal}"]
      ));

    home.packages = with pkgs; [
      signal-desktop
    ];
  };
}
