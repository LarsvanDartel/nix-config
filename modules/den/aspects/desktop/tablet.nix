# desktop.tablet — convertible support: accelerometer auto-rotation (iio-niri), and wvkbd kept running hidden for niri's tablet-mode switch events.
{...}: {
  den.aspects.desktop.tablet = {
    nixos = {
      hardware.sensor.iio.enable = true;
      services.iio-niri = {
        enable = true;
        extraArgs = ["--monitor" "eDP-1"];
      };
    };

    provides.to-users.homeManager = {pkgs, ...}: {
      systemd.user.services.wvkbd = {
        Unit = {
          Description = "wvkbd on-screen keyboard (shown in tablet mode)";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
        };
        Service = {
          ExecStart = "${pkgs.wvkbd}/bin/wvkbd-mobintl --hidden -L 300";
          Restart = "on-failure";
        };
        Install.WantedBy = ["graphical-session.target"];
      };
    };
  };
}
