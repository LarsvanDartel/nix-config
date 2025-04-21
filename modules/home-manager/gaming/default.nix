{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.gaming;
in {
  imports = [
    ./launchers
  ];

  options.modules.gaming = {
    enable = mkEnableOption "gaming";
  };

  config = mkIf cfg.enable {
    # Does nothing
  };
}
