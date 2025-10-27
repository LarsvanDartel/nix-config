{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;

  cfg = config.cosmos.cli.programs.eza;
in {
  options.cosmos.cli.programs.eza = {
    enable = mkEnableOption "eza";
  };

  config = mkIf cfg.enable {
    programs.eza = {
      enable = true;
      enableZshIntegration = config.cosmos.cli.shells.zsh.enable;
      colors = "auto";
      extraOptions = [
        "--group-directories-first"
        "--time-style=long-iso"
        "--header"
      ];
      git = mkDefault config.cosmos.cli.programs.git.enable;
      icons = "auto";
    };
  };
}
