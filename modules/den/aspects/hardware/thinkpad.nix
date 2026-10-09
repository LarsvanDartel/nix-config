# hardware.thinkpad — the sysfs/procfs write access ThinkPad control tools need.
# The noctalia plugins (battery-threshold, thinkpad-fan) run as the user, so
# these root-owned knobs are opened up declaratively.
{...}: {
  den.aspects.hardware.thinkpad.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # Store paths: udev has no PATH, and NixOS validates absolute udev paths at
    # build time, before /run/current-system exists.
    chgrp = lib.getExe' pkgs.coreutils "chgrp";
    chmod = lib.getExe' pkgs.coreutils "chmod";
  in {
    # udev re-applies this on every battery hotplug/resume; a one-off chmod
    # does not stick.
    users.groups.battery_ctl = {};
    users.users.${config.cosmos.user.name}.extraGroups = ["battery_ctl"];

    # procfs has no group ownership to hand out, so 0666 is the only option
    # (as upstream's setup script does).
    boot.extraModprobeConfig = ''
      options thinkpad_acpi fan_control=1
    '';

    services.udev.extraRules = ''
      SUBSYSTEM=="power_supply", KERNEL=="BAT*", \
        RUN+="${chgrp} battery_ctl /sys$devpath/charge_control_end_threshold", \
        RUN+="${chmod} g+w /sys$devpath/charge_control_end_threshold"

      SUBSYSTEM=="platform", DRIVERS=="thinkpad_acpi", RUN+="${chmod} 0666 /proc/acpi/ibm/fan"
    '';
  };
}
