# nvim trouble — diagnostics/symbols/LSP/quickfix panels on <leader>x; telescope's <C-t> sends results here.
{
  plugins = {
    trouble.enable = true;

    telescope.settings.defaults.mappings = let
      open = {__raw = "require('trouble.sources.telescope').open";};
    in {
      i."<C-t>" = open;
      n."<C-t>" = open;
    };
  };

  keymaps =
    map ({
      key,
      cmd,
      desc,
    }: {
      mode = "n";
      inherit key;
      action = "<cmd>Trouble ${cmd}<CR>";
      options.desc = desc;
    }) [
      {
        key = "<leader>xx";
        cmd = "diagnostics toggle";
        desc = "Workspace diagnostics";
      }
      {
        key = "<leader>xX";
        cmd = "diagnostics toggle filter.buf=0";
        desc = "Buffer diagnostics";
      }
      {
        key = "<leader>xs";
        cmd = "symbols toggle focus=false";
        desc = "Symbols";
      }
      {
        key = "<leader>xr";
        cmd = "lsp toggle focus=false win.position=right";
        desc = "LSP definitions/references";
      }
      {
        key = "<leader>xq";
        cmd = "qflist toggle";
        desc = "Quickfix list";
      }
      {
        key = "<leader>xl";
        cmd = "loclist toggle";
        desc = "Location list";
      }
    ];
}
