# roles.desktop — the graphical baseline: audio, bluetooth, networkmanager,
# fontconfig, nh, power, stylix + libinput. Desktop hosts include this; the
# primary user is lvdar with the desktop home role (wired at the host level).
{den, ...}: {
  den.aspects.roles.desktop = {
    includes = with den.aspects.desktop; [
      audio
      bluetooth
      networkmanager
      fontconfig
      nh
      power
      serial
      styling
    ];

    nixos = {...}: {
      services.libinput = {
        enable = true;
        mouse = {
          accelSpeed = "0.0";
          accelProfile = "flat";
        };
      };
    };
  };
}
