{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkBefore mkMerge;
  inherit (config.cosmos.home) username homeDirectory;

  cfg = config.cosmos.cli.programs.prompt.p10k;
in {
  options.cosmos.cli.programs.prompt.p10k = {
    enable = mkEnableOption "p10k shell prompt";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.files = [
      ".p10k.zsh"
      ".cache/p10k-instant-prompt-${username}.zsh"
    ];
    programs.zsh = {
      initContent = mkMerge [
        (mkBefore
          ''
            if [[ -r "${homeDirectory}/.cache/p10k-instant-prompt-${username}.zsh" ]];
            then
              source "${homeDirectory}/.cache/p10k-instant-prompt-${username}.zsh"
            fi
          '')
        ''
          [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
        ''
      ];

      zplug = {
        enable = true;
        plugins = [
          {
            name = "romkatv/powerlevel10k";
            tags = ["as:theme" "depth:1"];
          }
        ];
      };
    };
  };
}
