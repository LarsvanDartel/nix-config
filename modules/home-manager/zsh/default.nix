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
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      autocd = true;
      syntaxHighlighting.enable = true;

      dirHashes = {
        dev = "$HOME/dev";
        nix = "$HOME/nixos-config/";
      };

      shellAliases = {
        grep = "grep --color";
        ip = "ip --color";
      };
    };
  };
}
