# desktop.bluetooth
{...}: {
  den.aspects.desktop.bluetooth.nixos = {...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/bluetooth"];

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = false;
    };
  };
}
