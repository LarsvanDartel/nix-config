{
  config,
  lib,
  ...
}: let
  cfg = config.modules.virt-manager;
in {
  options.modules.virt-manager = {
    enable = lib.mkEnableOption "virt-manager";
  };

  config = lib.mkIf cfg.enable {
    programs.virt-manager.enable = true;
    host.sudo-groups = ["libvirtd"];
    virtualisation.libvirtd.enable = true;
    virtualisation.spiceUSBRedirection.enable = true;
  };
}
