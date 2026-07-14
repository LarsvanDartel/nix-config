# libvirt/virt-manager. The nixos half owns the daemon; the homeManager half
# carries the virt-manager dconf defaults (replacing the old cosmos.user.extraConfig
# bridge). A host wanting virtualisation imports both halves.
{...}: {
  flake.modules.nixos.virtualisation = {...}: {
    cosmos.user.extraGroups = ["libvirtd"];

    programs.virt-manager.enable = true;

    cosmos.system.impermanence.persist.directories = ["/var/lib/libvirt"];
    virtualisation = {
      libvirtd.enable = true;
      spiceUSBRedirection.enable = true;
    };
  };

  flake.modules.homeManager.virtualisation = {...}: {
    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = ["qemu:///system"];
        uris = ["qemu:///system"];
      };
    };
  };
}
