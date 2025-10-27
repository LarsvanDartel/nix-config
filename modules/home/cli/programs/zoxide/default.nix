{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.zoxide;
in {
  options.cosmos.cli.programs.zoxide = {
    enable = mkEnableOption "Enable zoxide";
  };
  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".local/share/zoxide"];
    programs.zoxide = {
      enable = true;
      enableZshIntegration = config.cosmos.cli.shells.zsh.enable;
      options = [
        "--cmd cd"
      ];
    };
  };
}
