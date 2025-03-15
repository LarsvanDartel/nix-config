{
  config,
  lib,
  ...
}: let
  cfg = config.modules.shell.prompt.p10k;
  inherit (config.home) username homeDirectory;
in {
  options.modules.shell.prompt.p10k = {
    enable = lib.mkEnableOption "p10k shell prompt";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.files = [
      ".p10k.zsh"
      ".cache/p10k-instant-prompt-${config.home.username}.zsh"
    ];
    programs.zsh = {
      initExtraFirst = ''
        if [[ -r "${homeDirectory}/.cache/p10k-instant-prompt-${username}.zsh" ]];
        then
          source "${homeDirectory}/.cache/p10k-instant-prompt-${username}.zsh"
        fi
      '';

      initExtra = ''
        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
      '';

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
