# desktop.serial — USB-serial device access for flashing tools (esptool,
# platformio, Web Serial installers like ESP Web Tools/crosspoint's). udev
# ships ttyACM*/ttyUSB* nodes as root:dialout 0660; browsers reaching the
# same device via the Web Serial API hit that identical permission check, not
# a separate one, so this one group fixes both esptool CLI and browser-based
# flashing.
{...}: {
  den.aspects.desktop.serial.nixos = {...}: {
    cosmos.user.extraGroups = ["dialout"];
  };
}
