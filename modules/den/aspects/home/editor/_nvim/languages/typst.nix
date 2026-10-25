# nvim typst — tinymist, typst-vim, the typst grammar and typstyle.
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe;
  inherit (lib.generators) mkLuaInline;

  cfg = config.cosmos.nvim.languages.typst;
in {
  config = mkIf cfg.enable {
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
          # exportPdf = "onType";
          semanticTokens = "disable";
          formatterMode = "typstyle";
          formatterProseWrap = true;
          formatterPrintWidth = 80;
          formatterIndentSize = 2;
          lint.enabled = true;
        };
        on_attach = mkLuaInline ''
          function(client, bufnr)
            vim.keymap.set("n", "<leader>lp", function()
              client:exec_cmd({
                title = "pin",
                command = "tinymist.pinMain",
                arguments = { vim.api.nvim_buf_get_name(0) },
              }, { bufnr = bufnr })
            end, { desc = "Pin main file", buffer = bufnr })

            vim.keymap.set("n", "<leader>lu", function()
              client:exec_cmd({
                title = "unpin",
                command = "tinymist.pinMain",
                arguments = { vim.v.null },
              }, { bufnr = bufnr })
            end, { desc = "Unpin main file", buffer = bufnr })

            vim.keymap.set("n", "<leader>lx", function()
              client:stop()
            end, { desc = "Stop tinymist", buffer = bufnr })
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
        # From PATH: the user's zathura is the themed wrapper, not pkgs.zathura.
        pdf_viewer = "zathura";
        conceal_math = 1;
      };
    };

    autoCmd = [
      {
        event = "FileType";
        pattern = "typst";
        callback.__raw = ''
          function(args)
            vim.keymap.set("n", "<leader>lw", "<cmd>TypstWatch<CR>", { desc = "Watch and open PDF", buffer = args.buf })
          end
        '';
      }
    ];
  };
}
