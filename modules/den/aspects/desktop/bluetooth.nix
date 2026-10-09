# desktop.bluetooth
{...}: {
  den.aspects.desktop.bluetooth.nixos = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/bluetooth"];

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # powerOnBoot alone fails on the ThinkPad: a soft-blocked thinkpad_acpi
    # rfkill keeps hci0 from appearing at all. The `+` matters — bluetoothd's
    # sandbox lacks CAP_NET_ADMIN, so without it ExecStartPre fails EPERM and
    # takes the unit down.
    systemd.services.bluetooth.serviceConfig.ExecStartPre = [
      "+${pkgs.util-linux}/bin/rfkill unblock bluetooth"
    ];
  };
}
