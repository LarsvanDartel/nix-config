{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) bool;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.programs.zathura;
in {
  options.cosmos.programs.zathura = {
    enable = mkEnableOption "zathura";
    defaultApplication = mkOption {
      type = bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    programs.zathura = {
      enable = true;
      options = {
        window-title-basename = true;
        selection-clipboard = "clipboard";
      };
    };
    xdg.mimeApps = mkIf cfg.defaultApplication {
      enable = true;
      defaultApplications = {
        "application/pdf" = ["org.pwmt.zathura.desktop"];
      };
    };
  };
}
