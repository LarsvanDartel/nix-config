{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.formal;

  vim-formal-package = pkgs.vimUtils.buildVimPlugin {
    name = "vim-formal-package";
    src = pkgs.fetchFromGitHub {
      owner = "lifepillar";
      repo = "vim-formal-package";
      rev = "59bac53fa82a9ea49a1137b3d619485068ffd518";
      hash = "sha256-3v9uhJs1926ngZZt7Md2zplm39bkPORjHIs0P+1+nSQ=";
    };

    postInstall = ''
      cd $out
      sh ./convert_to_plugin.sh
      rm convert_to_plugin.sh remove_plugin.sh
    '';
  };
in {
  options.cosmos.cli.programs.nvim.languages.formal = {
    enable = mkEnableOption "formal language support nvim";
  };
  config = mkIf cfg.enable {
    programs.nixvim = {
      extraPlugins = [vim-formal-package];
      filetype.extension = {
        pv = "proverif";
        pi = "proverif";
      };
    };
  };
}
