# roles.desktop — the graphical baseline (was the nixos `desktop` aggregate):
# audio, bluetooth, networkmanager, fontconfig, nh, stylix + libinput. Desktop
# hosts include this. The primary user is lvdar (default) with the desktop home
# role (wired at the host level).
{den, ...}: {
  den.aspects.roles.desktop = {
    includes = with den.aspects.desktop; [
      audio
      bluetooth
      networkmanager
      fontconfig
      nh
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
