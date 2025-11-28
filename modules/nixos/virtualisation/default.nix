{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.virtualisation;
in {
  options.cosmos.virtualisation = {
    enable = mkEnableOption "virtualisation";
  };

  config = mkIf cfg.enable {
    cosmos.user = {
      extraGroups = ["libvirtd"];
      extraConfig = {
        dconf.settings = {
          "org/virt-manager/virt-manager/connections" = {
            autoconnect = ["qemu:///system"];
            uris = ["qemu:///system"];
          };
        };
      };
    };

    cosmos.system.impermanence.persist.directories = ["/var/lib/libvirt"];

    programs.virt-manager.enable = true;

    virtualisation.libvirtd.enable = true;
    virtualisation.spiceUSBRedirection.enable = true;
  };
}
