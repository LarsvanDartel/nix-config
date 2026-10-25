# home.tmux — tmux as a nix-wrapper-modules package (`nix run .#tmux`); the
# wrapper holds the config and the base16 theme, home-manager only installs it.
# Host-specific additions go through `cosmos.cli.programs.tmux.wrapperModule`.
{
  inputs,
  cosmosStyling,
  ...
}: let
  mkTmux = pkgs:
    inputs.nix-wrapper-modules.wrappers.tmux.wrap {
      inherit pkgs;

      # The wrapper's defaults differ from tmux's; pinned to the old home-manager config.
      terminal = "screen";
      baseIndex = 0;
      paneBaseIndex = 0;
      mouse = false;
      escapeTime = 0;
      historyLimit = 2000;
      allowPassthrough = false;
      updateEnvironment = [];
      statusKeys = "vi";
      modeKeys = "vi";
      clock24 = true;
      disableConfirmationPrompt = true;

      plugins = [{plugin = pkgs.tmuxPlugins.yank;}];

      configBefore = ''
        bind -N "Select pane to the left of the active pane" h select-pane -L
        bind -N "Select pane below the active pane" j select-pane -D
        bind -N "Select pane above the active pane" k select-pane -U
        bind -N "Select pane to the right of the active pane" l select-pane -R

        bind -r -N "Resize the pane left by 5" H resize-pane -L 5
        bind -r -N "Resize the pane down by 5" J resize-pane -D 5
        bind -r -N "Resize the pane up by 5" K resize-pane -U 5
        bind -r -N "Resize the pane right by 5" L resize-pane -R 5
      '';

      configAfter = ''
        source-file ${cosmosStyling.colors pkgs {
          templateRepo = inputs.stylix.inputs.tinted-tmux;
          target = "base16";
        }}

        bind-key -T copy-mode-vi v send -X begin-selection
        bind-key -T copy-mode-vi V send -X select-line
        bind-key -T copy-mode-vi C-v send -X rectangle-toggle
        bind-key -T copy-mode-vi y send -X copy-selection-and-cancel
      '';
    };
in {
  perSystem = {pkgs, ...}: {packages.tmux = mkTmux pkgs;};

  den.aspects.home.tmux.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.cosmos.cli.programs.tmux.wrapperModule = lib.mkOption {
      type = lib.types.deferredModule;
      default = {};
      description = "Wrapper module layered onto this host's tmux (e.g. home.which-key).";
    };

    config.home.packages = [((mkTmux pkgs).wrap config.cosmos.cli.programs.tmux.wrapperModule)];
  };
}
