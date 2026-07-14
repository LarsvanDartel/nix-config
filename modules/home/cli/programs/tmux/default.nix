{...}: {
  flake.modules.homeManager.common = {pkgs, ...}: {
    programs.tmux = {
      enable = true;
      escapeTime = 0;
      clock24 = true;
      customPaneNavigationAndResize = true;
      disableConfirmationPrompt = true;
      keyMode = "vi";

      plugins = with pkgs.tmuxPlugins; [
        yank
      ];

      extraConfig = ''
        bind-key -T copy-mode-vi v send -X begin-selection
        bind-key -T copy-mode-vi V send -X select-line
        bind-key -T copy-mode-vi C-v send -X rectangle-toggle
        bind-key -T copy-mode-vi y send -X copy-selection-and-cancel
      '';
    };
  };
}
