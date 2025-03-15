{
  config,
  lib,
  ...
}: let
  cfg = config.modules.zsh;
in {
  options.modules.zsh = {
    enable = lib.mkEnableOption "zsh";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.files = [".zsh_history"];
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      history = {
        append = true;
        ignoreAllDups = true;
        ignoreDups = true;
        path = "${config.home.homeDirectory}/.zsh_history";
        share = true;
      };
      historySubstringSearch.enable = true;

      autocd = true;
      dirHashes = {
        dev = "$HOME/dev";
        nix = "$HOME/nixos-config/";
      };

      shellAliases = {
        grep = "grep --color";
        ip = "ip --color";
      };

      # oh-my-zsh = {
      #   enable = true;
      #   plugins = [];
      # };
    };
  };
}
