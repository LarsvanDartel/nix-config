{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.prompt.starship;
in {
  options.cli.programs.prompt.starship = {
    enable = mkEnableOption "starship shell prompt";
  };

  config = mkIf cfg.enable {
    programs.starship = {
      enable = true;
      enableZshIntegration = config.cli.shells.zsh.enable;
      settings = {};
    };
  };
}
