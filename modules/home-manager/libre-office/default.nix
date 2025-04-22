{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.libre-office;
in {
  options.modules.libre-office = {
    enable = mkEnableOption "LibreOffice";
  };

  config = mkIf cfg.enable {
    modules.persist.directories = [".config/libreoffice"];
    home.packages = with pkgs; [
      libreoffice-qt
      hunspell
      hunspellDicts.uk_UA
      hunspellDicts.th_TH
    ];
  };
}
