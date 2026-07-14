{...}: {
  flake.modules.nixos.desktop = {...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/bluetooth"];

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = false;
    };
  };
}
