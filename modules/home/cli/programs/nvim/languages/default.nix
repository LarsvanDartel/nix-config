{
  lib,
  pkgs,
  ...
}: let
  inherit (lib.meta) getExe';
in {
  imports = lib.cosmos.get-non-default-nix-files ./.;

  programs.nixvim = {
    diagnostic.settings.virtual_text = true;

    lsp = {
      inlayHints.enable = true;

      keymaps =
        lib.mapAttrsToList
        (
          key: props:
            {
              inherit key;
              options.silent = true;
            }
            // props
        )
        {
          "<leader>k".action.__raw = "function() vim.diagnostic.jump({ count=-1, float=true }) end";
          "<leader>j".action.__raw = "function() vim.diagnostic.jump({ count=1, float=true }) end";
          gd.lspBufAction = "definition";
          gD.lspBufAction = "references";
          gt.lspBufAction = "type_definition";
          gi.lspBufAction = "implementation";
          K.lspBufAction = "hover";
          gn.lspBufAction = "rename";
        };
    };

    plugins.treesitter = {
      enable = true;
      folding.enable = true;

      grammarPackages = [];
    };

    plugins.conform-nvim = {
      enable = true;
      luaConfig.pre = ''
        local slow_format_filetypes = {}
      '';
      settings = {
        formatters_by_ft = {
          "_" = [
            "squeeze_blanks"
            "trim_whitespace"
            "trim_newlines"
          ];
        };
        format_on_save =
          # Lua
          ''
            function(bufnr)
              if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
                return
              end

              if slow_format_filetypes[vim.bo[bufnr].filetype] then
                return
              end

              local function on_format(err)
                if err and err:match("timeout$") then
                  slow_format_filetypes[vim.bo[bufnr].filetype] = true
                end
              end

              return { timeout_ms = 200, lsp_fallback = true }, on_format
             end
          '';
        format_after_save =
          # Lua
          ''
            function(bufnr)
              if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
                return
              end

              if not slow_format_filetypes[vim.bo[bufnr].filetype] then
                return
              end

              return { lsp_fallback = true }
            end
          '';
        log_level = "warn";
        notify_on_error = false;
        notify_no_formatters = false;
        formatters = {
          squeeze_blanks = {
            command = getExe' pkgs.coreutils "cat";
          };
        };
      };
    };
  };
}
