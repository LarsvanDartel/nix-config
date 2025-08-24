{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.devenv;
in {
  options.cli.programs.devenv = {
    enable = mkEnableOption "devenv";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [devenv];
  };
}
