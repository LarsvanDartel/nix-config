{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;

  cfg = config.cli.programs.eza;
in {
  options.cli.programs.eza = {
    enable = mkEnableOption "eza";
  };

  config = mkIf cfg.enable {
    programs.eza = {
      enable = true;
      enableZshIntegration = config.cli.shells.zsh.enable;
      colors = "auto";
      extraOptions = [
        "--group-directories-first"
        "--time-style=long-iso"
        "--header"
      ];
      git = mkDefault config.cli.programs.git.enable;
      icons = "auto";
    };
  };
}
