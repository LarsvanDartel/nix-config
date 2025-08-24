{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.media.mpv;
in {
  options.media.mpv = {
    enable = mkEnableOption "mpv";
  };

  config = mkIf cfg.enable {
    programs.mpv.enable = true;
  };
}
