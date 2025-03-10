{
  config,
  lib,
  ...
}: let
  cfg = config.modules.networkmanager;
in {
  options.modules.networkmanager = {
    enable = lib.mkEnableOption "networkmanager";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = ["/etc/NetworkManager"];
    host.sudo-groups = ["networkmanager"];

    networking.networkmanager = {
      enable = true;
      wifi.powersave = true;
    };
  };
}
