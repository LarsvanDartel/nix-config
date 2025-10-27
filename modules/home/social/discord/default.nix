{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.social.discord;
in {
  options.cosmos.social.discord = {
    enable = mkEnableOption "discord";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".config/discord"];

    home.packages = with pkgs; [
      discord
    ];
  };
}
