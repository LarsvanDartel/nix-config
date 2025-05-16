{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.zoxide;
in {
  options.modules.zoxide = {
    enable = mkEnableOption "Enable zoxide";
  };
  config = mkIf cfg.enable {
    modules.persist.directories = [".local/share/zoxide"];
    programs.zoxide = {
      enable = true;
      enableZshIntegration = config.modules.shell.zsh.enable;
      options = [
        "--cmd cd"
      ];
    };
  };
}
