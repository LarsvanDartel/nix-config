{
  config,
  lib,
  ...
}: let
  cfg = config.modules.git.lazygit;
in {
  options.modules.git.lazygit = {
    enable = lib.mkEnableOption "lazygit";
  };

  config = lib.mkIf cfg.enable {
    programs.lazygit = {
      enable = true;
      settings = {
        disableStartupPopups = true;
        gui.skipDiscardChangeWarning = true;
      };
    };
  };
}
