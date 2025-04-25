{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.keyring;
in {
  options.modules.keyring = {
    enable = mkEnableOption "keyring";
  };

  options.systemwide.keyring = {
    enable = mkEnableOption "keyring";
  };

  config = mkIf cfg.enable {
    systemwide.keyring.enable = true;

    services.gnome-keyring.enable = true;
    home.packages = with pkgs; [
      gcr # Provides org.gnome.keyring.SystemPrompter
      seahorse # GUI for managing passwords and keys
    ];
  };
}
