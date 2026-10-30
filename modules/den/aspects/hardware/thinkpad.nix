# hardware.thinkpad — ThinkPad fan control: thinkpad_acpi's fan knob opened to the
# user for noctalia's thinkpad-fan plugin, which it also enables for every user.
{...}: {
  den.aspects.hardware.thinkpad = {
    nixos = {
      lib,
      pkgs,
      ...
    }: let
      # Store paths: udev has no PATH, and NixOS validates absolute udev paths at
      # build time, before /run/current-system exists.
      chmod = lib.getExe' pkgs.coreutils "chmod";
    in {
      # procfs has no group ownership to hand out, so 0666 is the only option
      # (as upstream's setup script does).
      boot.extraModprobeConfig = ''
        options thinkpad_acpi fan_control=1
      '';

      services.udev.extraRules = ''
        SUBSYSTEM=="platform", DRIVERS=="thinkpad_acpi", RUN+="${chmod} 0666 /proc/acpi/ibm/fan"
      '';
    };

    provides.to-users.homeManager.cosmos.desktops.noctalia.thinkpadFan = true;
  };
}
