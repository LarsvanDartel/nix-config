{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.terminal.programs.zoxide;
in {
  options.modules.terminal.programs.zoxide = {
    enable = mkEnableOption "Enable zoxide";
  };
  config = mkIf cfg.enable {
    modules.persist.directories = [".local/share/zoxide"];
    programs.zoxide = {
      enable = true;
      enableZshIntegration = config.modules.terminal.shell.zsh.enable;
      options = [
        "--cmd cd"
      ];
    };
  };
}
