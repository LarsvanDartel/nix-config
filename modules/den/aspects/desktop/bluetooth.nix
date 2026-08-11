# desktop.bluetooth
{...}: {
  den.aspects.desktop.bluetooth.nixos = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/bluetooth"];

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # powerOnBoot is necessary but not sufficient on the ThinkPad. It sets
    # Bluez's AutoEnable, which powers on adapters that *exist* — and the
    # thinkpad_acpi rfkill switch keeps hci0 from appearing at all when it is
    # soft-blocked. With the switch blocked, the daemon starts, finds nothing,
    # and anything looking for an adapter retries forever: kdeconnectd alone
    # was logging "No local bluetooth adapter found" twelve times a minute,
    # 16k warnings a day, which was 99% of this host's journal.
    #
    # Unblocking here rather than persisting /var/lib/systemd/rfkill, which is
    # the other way to do it: that directory is not in the persist layer, so
    # the saved state is discarded on every boot anyway, and restoring it would
    # only mean "whatever it was last time" rather than the "on at boot" this
    # is meant to express. Turning bluetooth off at runtime therefore does not
    # survive a reboot, which is the intended reading of the option name.
    # The `+` matters: nixpkgs runs bluetoothd with
    # CapabilityBoundingSet=CAP_NET_BIND_SERVICE, and writing /dev/rfkill needs
    # CAP_NET_ADMIN. An ExecStartPre inherits the unit's sandbox, so without
    # the prefix this fails with EPERM and takes the whole unit down with it.
    systemd.services.bluetooth.serviceConfig.ExecStartPre = [
      "+${pkgs.util-linux}/bin/rfkill unblock bluetooth"
    ];
  };
}
