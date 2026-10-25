# nvim formal — vim-formal-package syntax and ProVerif filetypes.
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.nvim.languages.formal;

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
  config = mkIf cfg.enable {
    extraPlugins = [vim-formal-package];
    filetype.extension = {
      pv = "proverif";
      pi = "proverif";
    };
  };
}
