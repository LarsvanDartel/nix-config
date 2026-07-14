{...}: {
  flake.modules.homeManager.p10k = {
    config,
    lib,
    ...
  }: let
    inherit (lib.modules) mkBefore mkMerge;
    inherit (config.home) username homeDirectory;
  in {
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
