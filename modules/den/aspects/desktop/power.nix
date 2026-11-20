# desktop.power — upower, power-profiles-daemon and user write access to the battery charge limit.
{...}: {
  den.aspects.desktop.power.nixos = {
    lib,
    pkgs,
    ...
  }: let
    # Store paths: udev has no PATH, and NixOS validates absolute udev paths at
    # build time, before /run/current-system exists.
    chgrp = lib.getExe' pkgs.coreutils "chgrp";
    chmod = lib.getExe' pkgs.coreutils "chmod";
  in {
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;

    # noctalia's battery-threshold plugin writes the limit as the user. udev re-applies the
    # permissions on every battery hotplug/resume; a one-off chmod does not stick.
    users.groups.battery_ctl = {};
    cosmos.user.extraGroups = ["battery_ctl"];
    services.udev.extraRules = ''
      SUBSYSTEM=="power_supply", KERNEL=="BAT*", \
        RUN+="${chgrp} battery_ctl /sys$devpath/charge_control_end_threshold", \
        RUN+="${chmod} g+w /sys$devpath/charge_control_end_threshold"
    '';
  };
}
