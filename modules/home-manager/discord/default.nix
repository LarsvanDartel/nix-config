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
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [".config/discord"];
    modules.unfree.allowedPackages = ["discord"];

    home.packages = with pkgs; [
      discord
    ];
  };
}
