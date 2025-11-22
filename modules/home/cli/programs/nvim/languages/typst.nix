{
  lib,
  pkgs,
  ...
}: let
  inherit (lib.meta) getExe;
in {
  programs.nixvim = {
    lsp.servers.tinymist = {
      enable = true;
      config = {
        cmd = [
          (getExe pkgs.tinymist)
        ];
        filetypes = [
          "typst"
        ];
        root_markers = [
          ".git"
        ];
      };
    };

    plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      typst
    ];

    plugins.conform-nvim.settings = {
      formatters_by_ft.typst = ["typstyle"];
      formatters.typstyle = {
        command = getExe pkgs.typstyle;
      };
    };

    plugins.typst-vim = {
      enable = true;
      settings = {
        cmd = getExe pkgs.typst;
        pdf_viewer = getExe pkgs.zathura;
        conceal_math = 1;
      };
    };
  };
}
