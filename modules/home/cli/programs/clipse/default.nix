{
  lib,
  config,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.clipse;
in {
  options.cli.programs.clipse = {
    enable = mkEnableOption "clipse";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.files = [".config/clipse/clipboard_history.json"];

    services.clipse.enable = true;
  };
}
