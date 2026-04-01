{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.tmux;
in {
  options.cosmos.cli.programs.tmux = {
    enable = mkEnableOption "tmux";
  };

  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      clock24 = true;
      customPaneNavigationAndResize = true;
      disableConfirmationPrompt = true;
      keyMode = "vi";

      plugins = with pkgs.tmuxPlugins; [
        yank
        tmux-which-key
        tmux-sessionx
      ];
    };
  };
}
