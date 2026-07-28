# home.zsh (was the zsh contribution to homeManager.common).
{...}: {
  den.aspects.home.zsh.homeManager = {
    config,
    lib,
    ...
  }: let
    inherit (lib.types) str lines attrsOf;
    inherit (lib.options) mkOption;
    inherit (lib.modules) mkMerge mkAfter;
    inherit (lib.strings) optionalString;
    inherit (config.cosmos.user) home;
  in {
    options.cosmos.cli.shells.zsh = {
      aliases = mkOption {
        type = attrsOf str;
        default = {};
        description = "shell aliases";
      };
      initContent = mkOption {
        type = lines;
        default = "";
        description = "shell init content";
      };
    };

    config = {
      cosmos.system.impermanence.persist.directories = [".zplug"];

      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;

        history = let
          active = config.cosmos.system.impermanence.active;
        in {
          append = true;
          ignoreAllDups = true;
          ignoreDups = true;
          path = "${optionalString active "/persist"}${home}/.zsh_history";
          share = true;
        };
        historySubstringSearch.enable = true;

        autocd = true;
        dirHashes = {
          dev = "${home}/dev";
          nix = "${home}/nixos-config/";
        };

        shellAliases = config.cosmos.cli.shells.zsh.aliases;
        initContent = mkMerge [
          config.cosmos.cli.shells.zsh.initContent
          (mkAfter ''
            setopt dotglob
          '')
        ];
      };
    };
  };
}
