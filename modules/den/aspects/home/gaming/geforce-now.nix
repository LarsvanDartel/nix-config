# home.geforce-now
{...}: {
  den.aspects.home.geforce-now.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkPackageOption mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.gaming.launchers.geforce-now;
  in {
    options.cosmos.gaming.launchers.geforce-now = {
      gamescope = mkOption {
        type = bool;
        default = true;
        description = "Wrap GeForce Now with Gamescope.";
      };
      package = mkPackageOption pkgs "gfn-electron" {};
    };

    config = {
      cosmos.system.impermanence.persist.directories = [".config/GeForce Now"];
      home.packages = [cfg.package];

      xdg.desktopEntries."geforce-now" = mkIf cfg.gamescope {
        name = "GeForce Now (Gamescope)";
        comment = "Stream games using the Nvidia GeForce Now service";
        type = "Application";
        exec = "${pkgs.gamescope}/bin/gamescope -W 1920 -H 1080 -r 60 --backend sdl -- ${cfg.package}/bin/geforcenow-electron";
        icon = "${cfg.package}/share/icons/hicolor/512x512/apps/geforcenow-electron.png";
        categories = ["Game" "Network"];
      };
    };
  };
}
