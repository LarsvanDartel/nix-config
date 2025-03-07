{
  config,
  lib,
  ...
}: let
  cfg = config.modules.nh;
in {
  options.modules.nh = {
    enable = lib.mkEnableOption "nh";
  };

  config = lib.mkIf cfg.enable {
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "all --keep 4";
    };
  };
}
