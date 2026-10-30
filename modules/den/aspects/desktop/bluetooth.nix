# desktop.bluetooth
{...}: {
  den.aspects.desktop.bluetooth.nixos = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/bluetooth"];

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # powerOnBoot alone is not enough: a soft-blocked rfkill (seen on the
    # ThinkPad P1) keeps hci0 from appearing at all. The `+` matters —
    # bluetoothd's sandbox lacks CAP_NET_ADMIN, so without it ExecStartPre
    # fails EPERM and takes the unit down.
    systemd.services.bluetooth.serviceConfig.ExecStartPre = [
      "+${pkgs.util-linux}/bin/rfkill unblock bluetooth"
    ];
  };
}
