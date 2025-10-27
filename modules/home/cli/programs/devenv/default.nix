{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.devenv;
in {
  options.cosmos.cli.programs.devenv = {
    enable = mkEnableOption "devenv";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [devenv];
  };
}
