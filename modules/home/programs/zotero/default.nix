{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.programs.zotero;
in {
  options.cosmos.programs.zotero = {
    enable = mkEnableOption "zotero";
  };

  config = mkIf cfg.enable {
    home.packages = [pkgs.zotero];

    cosmos.system.impermanence.persist.directories = ["Zotero" ".zotero"];
  };
}
