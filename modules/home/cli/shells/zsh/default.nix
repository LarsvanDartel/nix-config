{
  config,
  lib,
  ...
}: let
  inherit (lib.types) str lines attrsOf;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf;
  inherit (config.home) homeDirectory;

  cfg = config.cli.shells.zsh;
in {
  options.cli.shells.zsh = {
    enable = mkEnableOption "zsh";
    aliases = mkOption {
      type = attrsOf str;
      description = "shell aliases";
    };

    initContent = mkOption {
      type = lines;
      default = "";
      description = "shell init content";
    };
  };

  config = mkIf cfg.enable {
    system.impermanence.persist = {
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

      shellAliases = cfg.aliases;
      inherit (cfg) initContent;
    };
  };
}
