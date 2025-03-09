{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.firefox;
in {
  options.modules.firefox = {
    enable = lib.mkEnableOption "firefox browser";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      ".mozilla"
    ];
    programs.firefox.enable = true;
  };
}
