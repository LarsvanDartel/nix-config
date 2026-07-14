{...}: {
  flake.modules.nixos.desktop = {
    config,
    lib,
    ...
  }: let
    inherit (lib.types) str;
    inherit (lib.options) mkOption;

    cfg = config.cosmos.cli.programs.nh;
  in {
    options.cosmos.cli.programs.nh = {
      flake-dir = mkOption {
        type = str;
        default = "/etc/nixos";
        description = "Path to the flake directory.";
      };
    };

    config = {
      programs.nh = {
        enable = true;
        clean.enable = true;
        clean.extraArgs = "--keep-since 4d --keep 3";
        flake = cfg.flake-dir;
      };
    };
  };
}
