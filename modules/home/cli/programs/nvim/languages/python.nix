{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe getExe';

  cfg = config.cosmos.cli.programs.nvim.languages.python;
in {
  options.cosmos.cli.programs.nvim.languages.python = {
    enable = mkEnableOption "python language support nvim";
  };
  config = mkIf cfg.enable {
    programs.nixvim = {
      lsp.servers.basedpyright = {
        enable = true;
        packageFallback = true;
        config = {
          cmd = [(getExe' pkgs.basedpyright "basedpyright-langserver") "--stdio"];
          filetypes = ["python"];
          root_markers = [
            "pyproject.toml"
            "setup.py"
            "setup.cfg"
            "requirements.txt"
            "Pipfile"
            "pyrightconfig.json"
            ".git"
          ];
          init_options = {
            analysis = {
              autoSearchPaths = true;
              useLibraryCodeForTypes = true;
              diagnosticMode = "openFilesOnly";
            };
          };
          on_attach.__raw = ''
            function(client, bufnr)
              vim.api.nvim_buf_create_user_command(bufnr, 'LspPyrightOrganizeImports', function()
                local params = {
                  command = 'basedpyright.organizeimports',
                  arguments = { vim.uri_from_bufnr(bufnr) },
                }

                -- Using client.request() directly because "basedpyright.organizeimports" is private
                -- (not advertised via capabilities), which client:exec_cmd() refuses to call.
                -- https://github.com/neovim/neovim/blob/c333d64663d3b6e0dd9aa440e433d346af4a3d81/runtime/lua/vim/lsp/client.lua#L1024-L1030
                client.request('workspace/executeCommand', params, nil, bufnr)
              end, {
                desc = 'Organize Imports',
              })
            end
          '';
        };
      };

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        python
      ];

      plugins.conform-nvim.settings = {
        formatters_by_ft.python = ["black"];
        formatters.black = {
          command = getExe pkgs.black;
        };
      };
    };
  };
}
