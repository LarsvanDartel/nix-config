{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.fd;
in {
  options.cli.programs.fd = {
    enable = mkEnableOption "fd";
  };

  config = mkIf cfg.enable {
    programs.fd = {
      enable = true;
    };
  };
}
