# hardware.thinkpad — the sysfs/procfs write access ThinkPad control tools need.
#
# Both knobs below are root-owned by default, and the noctalia plugins that use
# them (battery-threshold, thinkpad-fan) are plain QML running as the user with
# no privilege escalation — upstream ships shell scripts that set this up by
# hand. This is the declarative equivalent.
{...}: {
  den.aspects.hardware.thinkpad.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # Absolute, because udev has no PATH. Store paths rather than
    # /run/current-system/sw/bin: NixOS validates every absolute path in a udev
    # rule at build time, and the current system does not exist yet then.
    chgrp = lib.getExe' pkgs.coreutils "chgrp";
    chmod = lib.getExe' pkgs.coreutils "chmod";
  in {
    # Charge thresholds: hand the sysfs attribute to a group instead of making
    # it world-writable. udev re-applies this on every battery hotplug/resume,
    # which is why a one-off chmod does not stick.
    users.groups.battery_ctl = {};
    users.users.${config.cosmos.user.name}.extraGroups = ["battery_ctl"];

    # Fan control is refused by the driver unless explicitly opted in, and the
    # interface is procfs, which has no group ownership to hand out — 0666 is
    # what upstream's setup script does and the only option here.
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
