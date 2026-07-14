# The `desktop` aggregate: adds the graphical baseline on top of `common`
# (fontconfig, styling, networkmanager, audio, bluetooth, nh all self-register
# into `flake.modules.nixos.desktop`). Desktop hosts import both `common` and
# `desktop`. This file adds the profile-level glue + the desktop home aggregate.
{config, ...}: let
  home = config.flake.modules.homeManager;
in {
  flake.modules.nixos.desktop = {config, ...}: {
    cosmos.user.name = "lvdar";

    services.libinput = {
      enable = true;
      mouse = {
        accelSpeed = "0.0";
        accelProfile = "flat";
      };
    };

    # The primary user's home gets the desktop home aggregate.
    home-manager.users.${config.cosmos.user.name}.imports = [home.desktop];
  };
}
