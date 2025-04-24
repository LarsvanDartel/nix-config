{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.zathura;
in {
  options.modules.zathura = {
    enable = mkEnableOption "zathura";
  };

  config = mkIf cfg.enable {
    programs.zathura = {
      enable = true;
      options = {
        guioptions = "hv"; # Horizontal and vertical scrollbars
      };
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "application/pdf" = "zathura";
      };
    };
  };
}
