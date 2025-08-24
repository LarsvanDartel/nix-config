{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.hardware.networking;
in {
  options.hardware.networking = {
    enable = mkEnableOption "networkmanager";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = ["/etc/NetworkManager"];
    user.extraGroups = ["networkmanager"];

    networking = {
      firewall.enable = true;
      networkmanager.enable = true;
    };
  };
}
