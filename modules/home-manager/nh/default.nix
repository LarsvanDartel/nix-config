{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) str;
  inherit (lib.modules) mkIf;

  cfg = config.modules.nh;
in {
  options.modules.nh = {
    enable = mkEnableOption "nh";
    flake-dir = mkOption {
      type = str;
      default = "/etc/nixos";
      description = "Path to the flake directory.";
    };
  };

  config = mkIf cfg.enable {
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = cfg.flake-dir;
    };
  };
}
