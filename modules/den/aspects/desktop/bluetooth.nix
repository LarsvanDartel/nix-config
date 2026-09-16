# desktop.bluetooth
{...}: {
  den.aspects.desktop.bluetooth.nixos = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/bluetooth"];

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # powerOnBoot is necessary but not sufficient on the ThinkPad: it sets
    # Bluez's AutoEnable for adapters that *exist*, but a soft-blocked
    # thinkpad_acpi rfkill keeps hci0 from appearing at all — the daemon
    # starts, finds nothing, and everything looking for an adapter retries
    # forever (kdeconnectd alone logged "No local bluetooth adapter found"
    # 16k times a day). Unblocking here rather than persisting
    # /var/lib/systemd/rfkill: that dir is not in the persist layer, and "on at
    # boot" is what this should mean. The `+` matters — bluetoothd's sandbox
    # lacks CAP_NET_ADMIN, which writing /dev/rfkill needs; without the prefix
    # the ExecStartPre fails EPERM and takes the whole unit down.
    systemd.services.bluetooth.serviceConfig.ExecStartPre = [
      "+${pkgs.util-linux}/bin/rfkill unblock bluetooth"
    ];
  };
}
