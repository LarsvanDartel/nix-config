{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.hardware.networking;
in {
  options.cosmos.hardware.networking = {
    enable = mkEnableOption "networkmanager";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = ["/etc/NetworkManager"];
    cosmos.user.extraGroups = ["networkmanager"];

    networking = {
      firewall.enable = true;
      networkmanager = {
        enable = true;
        plugins = [pkgs.networkmanager-openvpn];
      };
      nameservers = ["9.9.9.9"];
    };
  };
}
