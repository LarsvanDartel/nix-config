{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (config.home) homeDirectory;

  shellCfg = config.modules.terminal.shell;
  cfg = shellCfg.zsh;
in {
  options.modules.terminal.shell.zsh = {
    enable = mkEnableOption "zsh";
  };

  config = mkIf cfg.enable {
    modules.persist = {
      directories = [".zplug"];
      files = [".zsh_history"];
    };

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      history = {
        append = true;
        ignoreAllDups = true;
        ignoreDups = true;
        path = "${homeDirectory}/.zsh_history";
        share = true;
      };
      historySubstringSearch.enable = true;

      autocd = true;
      dirHashes = {
        dev = "${homeDirectory}/dev";
        nix = "${homeDirectory}/nixos-config/";
      };

      shellAliases = shellCfg.aliases;
      inherit (shellCfg) initContent;
    };
  };
}
