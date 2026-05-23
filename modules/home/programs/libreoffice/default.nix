{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.programs.libreoffice;
in {
  options.cosmos.programs.libreoffice = {
    enable = mkEnableOption "libreoffice";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".config/libreoffice/"];

    home.packages = with pkgs; [
      libreoffice-qt
      hunspell
      hunspellDicts.uk_UA
      hunspellDicts.th_TH
    ];
  };
}
