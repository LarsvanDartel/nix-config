{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.file-manager.ranger;
in {
  options.modules.file-manager.ranger = {
    enable = mkEnableOption "ranger file manager";
  };
  config = mkIf cfg.enable {
    programs.ranger = {
      enable = true;
    };
  };
}
