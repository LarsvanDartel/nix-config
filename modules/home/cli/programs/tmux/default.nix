# tmux. Unlike the other programs, tmux has a second contributor to
# `programs.tmux` (the desktop-only which-key plugin) plus the stylix tmux
# target, and splitting it into a named module imported by `common` reorders the
# merged plugin/source list in tmux.conf. To keep deployment byte-identical we
# use dual-definition instead: `common` sets programs.tmux directly (exactly as
# before) and a standalone `tmux` module carries the same config for wrapping.
# The shared `tmuxConfig` avoids duplication.
{...}: let
  tmuxConfig = pkgs: {
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
in {
  flake.modules.homeManager.tmux = {pkgs, ...}: {
    programs.tmux = tmuxConfig pkgs;
  };

  flake.modules.homeManager.common = {pkgs, ...}: {
    programs.tmux = tmuxConfig pkgs;
  };
}
