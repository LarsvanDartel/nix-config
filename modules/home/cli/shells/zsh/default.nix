{
  config,
  lib,
  ...
}: let
  inherit (lib.types) str lines attrsOf;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkMerge mkAfter;
  inherit (lib.strings) optionalString;
  inherit (config.cosmos.user) home;

  cfg = config.cosmos.cli.shells.zsh;
in {
  options.cosmos.cli.shells.zsh = {
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
    cosmos.system.impermanence.persist = {
      directories = [".zplug"];
    };

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      history = let
        impermanence = config.cosmos.system.impermanence.enable;
      in {
        append = true;
        ignoreAllDups = true;
        ignoreDups = true;
        path = "${optionalString impermanence "/persist"}${home}/.zsh_history";
        share = true;
      };
      historySubstringSearch.enable = true;

      autocd = true;
      dirHashes = {
        dev = "${home}/dev";
        nix = "${home}/nixos-config/";
      };

      shellAliases = cfg.aliases;
      initContent = mkMerge [
        cfg.initContent
        (mkAfter ''
          setopt dotglob
        '')
      ];
    };
  };
}
