{
  lib,
  pkgs,
  ...
}: let
  inherit (lib.meta) getExe;
in {
  programs.nixvim = {
    plugins.rustaceanvim = {
      enable = true;
      settings = {
        server = {
          on_attach = ''
            function(_, bufnr)
              vim.keymap.set("n", "<leader>cR", function()
                vim.cmd.RustLsp("codeAction")
              end, { desc = "Code Action", buffer = bufnr })
              vim.keymap.set("n", "<leader>dr", function()
                vim.cmd.RustLsp("debuggables")
              end, { desc = "Rust Debuggables", buffer = bufnr })
            end
          '';
          default_settings = {
            rust-analyzer = {
              cargo = {
                allFeatures = true;
                loadOutDirsFromCheck = true;
                buildScripts = {
                  enable = true;
                };
              };
              check = {
                command = "clippy";
              };
              inlayHints = {
                lifetimeElisionHints = {
                  enable = "always";
                };
              };
              checkOnSave = true;
              diagnostics.enable = true;
              procMacro = {
                enable = true;
              };
              files = {
                exclude = [
                  ".direnv"
                  ".git"
                  ".jj"
                  ".github"
                  ".gitlab"
                  "bin"
                  "node_modules"
                  "target"
                  "venv"
                  ".venv"
                ];
                watcher = "client";
              };
            };
          };
          standalone = false;
        };
      };
    };

    plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      rust
    ];

    plugins.conform-nvim.settings = {
      formatters_by_ft.rust = ["rustfmt"];
      formatters.rustfmt = {
        command = getExe pkgs.rustfmt;
      };
    };
  };
}
