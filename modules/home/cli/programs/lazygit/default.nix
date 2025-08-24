{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.lazygit;
in {
  options.cli.programs.lazygit = {
    enable = mkEnableOption "lazygit";
  };

  config = mkIf cfg.enable {
    programs.lazygit = {
      enable = true;
      settings = {
        disableStartupPopups = true;
        gui.skipDiscardChangeWarning = true;
      };
    };
  };
}
