{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.zoxide;
in {
  options.cli.programs.zoxide = {
    enable = mkEnableOption "Enable zoxide";
  };
  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [".local/share/zoxide"];
    programs.zoxide = {
      enable = true;
      enableZshIntegration = config.cli.shells.zsh.enable;
      options = [
        "--cmd cd"
      ];
    };
  };
}
