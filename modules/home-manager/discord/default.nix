{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.discord;
in {
  options.modules.discord = {
    enable = lib.mkEnableOption "discord";
    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Autostart discord";
    };
  };

  config = lib.mkIf cfg.enable {
    modules = {
      persist.directories = [".config/discord"];
      graphical.startupCommands =
        lib.mkIf cfg.autostart
        (lib.mkOrder 800 ["${pkgs.discord}/bin/discord"]);
      unfree.allowedPackages = ["discord"];
    };

    home.packages = with pkgs; [
      discord
    ];
  };
}
