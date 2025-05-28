{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.virt-manager;
in {
  options.modules.virt-manager = {
    enable = mkEnableOption "virt-manager";
  };
  options.systemwide.virt-manager = {
    enable = mkEnableOption "virt-manager";
  };

  config = mkIf cfg.enable {
    systemwide.virt-manager.enable = true;

    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = ["qemu:///system"];
        uris = ["qemu:///system"];
      };
    };
  };
}
