{
  lib,
  config,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.btop;
in {
  options.cli.programs.btop = {
    enable = mkEnableOption "btop";
  };

  config = mkIf cfg.enable {
    programs.btop.enable = true;
  };
}
