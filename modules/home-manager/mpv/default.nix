{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.mpv;
in {
  options.modules.mpv = {
    enable = mkEnableOption "mpv";
  };

  config = mkIf cfg.enable {
    programs.mpv.enable = true;
  };
}
