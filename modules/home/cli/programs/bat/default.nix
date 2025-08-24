{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.bat;
in {
  options.cli.programs.bat = {
    enable = mkEnableOption "bat";
  };

  config = mkIf cfg.enable {
    cli.shells.zsh.initContent = ''
      eval "$(batpipe)"
      eval "$(batman --export-env)"
    '';

    home.sessionVariables = mkIf config.cli.programs.git.delta.enable {
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
