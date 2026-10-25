# nvim rust — rustaceanvim, the rust grammar and rustfmt.
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe;

  cfg = config.cosmos.nvim.languages.rust;
in {
  config = mkIf cfg.enable {
    plugins.rustaceanvim = {
      enable = true;
      settings = {
        server = {
          on_attach = ''
            function(_, bufnr)
              local function map(key, cmd, desc)
                vim.keymap.set("n", key, function() vim.cmd.RustLsp(cmd) end, { desc = desc, buffer = bufnr })
              end
              map("<leader>la", "codeAction", "Code action (grouped)")
              map("<leader>le", "explainError", "Explain error")
              map("<leader>lm", "expandMacro", "Expand macro")
              map("<leader>lo", "openDocs", "Open docs.rs")
              map("<leader>lc", "openCargo", "Open Cargo.toml")
              map("<leader>lt", "testables", "Testables")
              map("<leader>lp", "parentModule", "Parent module")
              map("<leader>dR", "debuggables", "Rust debuggables")
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
