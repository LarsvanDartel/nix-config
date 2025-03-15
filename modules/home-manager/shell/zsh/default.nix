{
  config,
  lib,
  ...
}: let
  cfg = config.modules.shell.zsh;
  inherit (config.home) homeDirectory;
in {
  options.modules.shell.zsh = {
    enable = lib.mkEnableOption "zsh";
  };

  config = lib.mkIf cfg.enable {
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

      shellAliases = {
        grep = "grep --color";
        ip = "ip --color";
      };
    };
  };
}
