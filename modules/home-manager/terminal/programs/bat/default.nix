{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.terminal.programs.bat;
in {
  options.modules.terminal.programs.bat = {
    enable = mkEnableOption "bat";
  };

  config = mkIf cfg.enable {
    modules.terminal.shell.initContent = ''
      eval "$(batpipe)"
      eval "$(batman --export-env)"
    '';

    home.sessionVariables = mkIf config.modules.git.delta.enable {
      BATDIFF_USE_DELTA = "true";
    };

    programs.bat = {
      enable = true;

      extraPackages = with pkgs.bat-extras; [
        batgrep
        batman
        batpipe
        batwatch
        batdiff
      ];
    };
  };
}
