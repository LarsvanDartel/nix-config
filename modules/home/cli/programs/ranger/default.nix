{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.ranger;
in {
  options.cli.programs.ranger = {
    enable = mkEnableOption "ranger file manager";
  };
  config = mkIf cfg.enable {
    programs.ranger = {
      enable = true;
    };
  };
}
