# desktop.bluetooth — bluez with blueman, powered and unblocked at boot.
{...}: {
  den.aspects.desktop.bluetooth.nixos = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/bluetooth"];

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # A soft-blocked rfkill hides hci0 despite powerOnBoot. Keep the `+`: bluetoothd's sandbox
    # lacks CAP_NET_ADMIN, so an unprivileged ExecStartPre fails EPERM and takes the unit down.
    systemd.services.bluetooth.serviceConfig.ExecStartPre = [
      "+${pkgs.util-linux}/bin/rfkill unblock bluetooth"
    ];
  };
}
