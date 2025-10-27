{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.bat;
in {
  options.cosmos.cli.programs.bat = {
    enable = mkEnableOption "bat";
  };

  config = mkIf cfg.enable {
    cosmos.cli.shells.zsh.initContent = ''
      eval "$(batpipe)"
      eval "$(batman --export-env)"
    '';

    home.sessionVariables = mkIf config.cosmos.cli.programs.git.delta.enable {
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
