# home.geforce-now — GeForce NOW in a Chromium app window. The web client is
# the only Linux client nixpkgs has: gfn-electron was dropped as abandoned, and
# NVIDIA's native app ships only as a Flatpak. Firefox-based browsers are refused.
{...}: {
  den.aspects.home.geforce-now.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkPackageOption;
    inherit (lib.meta) getExe;

    cfg = config.cosmos.gaming.launchers.geforce-now;
    profile = "${config.xdg.configHome}/geforce-now";
  in {
    options.cosmos.gaming.launchers.geforce-now = {
      package = mkPackageOption pkgs "chromium" {};
    };

    config = {
      # Its own profile keeps the NVIDIA login and is the only Chromium state.
      cosmos.system.impermanence.persist.directories = [".config/geforce-now"];

      xdg.desktopEntries."geforce-now" = {
        name = "GeForce NOW";
        comment = "Stream games using the NVIDIA GeForce NOW service";
        type = "Application";
        exec = "${getExe cfg.package} --user-data-dir=${profile} --app=https://play.geforcenow.com";
        # gfn-electron's icon at a pinned commit: an immutable URL, unlike
        # play.geforcenow.com's assets, whose names change with redesigns.
        icon = pkgs.fetchurl {
          name = "geforce-now.png";
          url = "https://raw.githubusercontent.com/hmlendea/gfn-electron/19ae6667bdf5c5ae774e1f9e791c2b2485fff075/icon.png";
          hash = "sha256-WCrUuwc5JuUdisqgq4GqcKHb5HNu2gzxMLauaJmCt6A=";
        };
        categories = ["Game" "Network"];
      };
    };
  };
}
