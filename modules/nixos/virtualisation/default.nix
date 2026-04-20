{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkMerge;

  cfg = config.cosmos.virtualisation;
in {
  options.cosmos.virtualisation = {
    enable = mkEnableOption "virtualisation";
    containers.enable = mkEnableOption "containers";
  };

  config = mkMerge [
    (mkIf cfg.enable {
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

      programs.virt-manager.enable = true;

      cosmos.system.impermanence.persist.directories = ["/var/lib/libvirt"];
      virtualisation = {
        libvirtd.enable = true;
        spiceUSBRedirection.enable = true;
      };
    })
    (mkIf cfg.containers.enable {
      cosmos.user.extraGroups = ["podman" "kvm"];
      boot.kernelModules = ["kvm-intel"];
      virtualisation = {
        containers.enable = true;
        podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings.dns_enabled = true;
        };
      };
    })
  ];
}
