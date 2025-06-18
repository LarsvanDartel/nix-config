{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.development.devenv;
in {
  options.modules.development.devenv = {
    enable = lib.mkEnableOption "devenv";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [devenv];
  };
}
