{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.social.discord;
in {
  options.social.discord = {
    enable = mkEnableOption "discord";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [".config/discord"];

    home.packages = with pkgs; [
      discord
    ];
  };
}
