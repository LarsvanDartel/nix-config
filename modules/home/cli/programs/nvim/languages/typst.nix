{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe;
  inherit (lib.generators) mkLuaInline;

  cfg = config.cosmos.cli.programs.nvim.languages.typst;
in {
  options.cosmos.cli.programs.nvim.languages.typst = {
    enable = mkEnableOption "typst language support nvim";
  };
  config = mkIf cfg.enable {
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
            "main.typ"
          ];
          settings = {
            exportPdf = "onType";
            semanticTokens = "disable";
            formatterMode = "typstyle";
            formatterProseWrap = true;
            formatterPrintWidth = 80;
            formatterIndentSize = 4;
          };
          on_attach = mkLuaInline ''
            function(client, bufnr)
              vim.keymap.set("n", "<leader>tp", function()
                client:exec_cmd({
                  title = "pin",
                  command = "tinymist.pinMain",
                  arguments = { vim.api.nvim_buf_get_name(0) },
                }, { bufnr = bufnr })
              end, { desc = "[T]inymist [P]in", noremap = true })

              vim.keymap.set("n", "<leader>tu", function()
                client:exec_cmd({
                  title = "unpin",
                  command = "tinymist.pinMain",
                  arguments = { vim.v.null },
                }, { bufnr = bufnr })
              end, { desc = "[T]inymist [U]npin", noremap = true })
            end
          '';
        };
      };

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        typst
      ];

      plugins.conform-nvim.settings = {
        formatters_by_ft.typst = ["typstyle"];
        formatters.typstyle = {
          command = "${getExe pkgs.typstyle} -- wrap-lines";
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
  };
}
