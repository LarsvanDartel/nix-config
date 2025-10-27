{
  lib,
  config,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.clipse;
in {
  options.cosmos.cli.programs.clipse = {
    enable = mkEnableOption "clipse";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.files = [".config/clipse/clipboard_history.json"];

    services.clipse.enable = true;
  };
}
