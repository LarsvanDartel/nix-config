{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.firefox;
in {
  options.firefox = {
    enable = lib.mkEnableOption "Enable Firefox browser";
  };

  config = lib.mkIf cfg.enable {
    programs.firefox.enable = true;
  };
}
