{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.rocq;
in {
  options.cosmos.cli.programs.nvim.languages.rocq = {
    enable = mkEnableOption "rocq language support nvim";
  };
  config = mkIf cfg.enable {
    programs.nixvim = {
      extraPlugins = [
        (pkgs.vimPlugins.Coqtail.overrideAttrs
          (old: {
            postPatch = ''
              substituteInPlace autoload/coqtail.vim \
                --replace "expand('<sfile>:p:h:h')" "fnamemodify(resolve(expand('<sfile>:p')), ':h:h')"
            '';
          }))
      ];
      # extraConfigLua = ''
      #   require('my-plugin').setup({foo = "bar"})
      # '';
    };
  };
}
