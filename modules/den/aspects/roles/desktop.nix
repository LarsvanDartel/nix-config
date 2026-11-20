# roles.desktop — the graphical baseline desktop hosts include.
{den, ...}: {
  den.aspects.roles.desktop = {
    includes = with den.aspects.desktop; [
      audio
      bluetooth
      networkmanager
      fontconfig
      nh
      power
      printing
      serial
      styling
    ];

    nixos = {...}: {
      programs.ssh.startAgent = true;

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
