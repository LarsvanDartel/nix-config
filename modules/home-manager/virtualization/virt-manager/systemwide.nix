{
  virt-manager = {
    modules.persist.directories = ["/var/lib/libvirt"];

    programs.virt-manager.enable = true;

    host.sudo-groups = ["libvirtd"];

    virtualisation.libvirtd.enable = true;
    virtualisation.spiceUSBRedirection.enable = true;
  };
}
