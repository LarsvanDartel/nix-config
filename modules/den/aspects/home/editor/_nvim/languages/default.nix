# nvim languages — LSP, diagnostics, treesitter and conform; per-language files are imported here.
{
  lib,
  pkgs,
  ...
}: let
  inherit (lib.meta) getExe';

  # conform's format-on-save reads these flags; the <leader>u toggles flip them.
  autoformatGuard = ''
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return
    end
  '';
in {
  imports =
    map (n: ./. + "/${n}")
    (builtins.attrNames (lib.filterAttrs (n: t: t == "regular" && n != "default.nix" && lib.hasSuffix ".nix" n) (builtins.readDir ./.)));

  # Rounds every float without its own border: hover, signature help, diagnostics.
  opts.winborder = "rounded";

  diagnostic.settings = {
    severity_sort = true;
    signs = true;
    underline = true;
    virtual_text = true;
    virtual_lines = false;
    float.source = "if_many";
  };

  # 0.12 maps K, grn, gra, grr, gri, grt, gO and insert <C-s> on attach; only
  # what it lacks is added here.
  lsp = {
    inlayHints.enable = true;

    keymaps = [
      {
        mode = "n";
        key = "gd";
        lspBufAction = "definition";
        options.desc = "Goto definition";
      }
      {
        mode = "n";
        key = "gD";
        lspBufAction = "declaration";
        options.desc = "Goto declaration";
      }
      {
        mode = ["n" "x"];
        key = "<leader>la";
        lspBufAction = "code_action";
        options.desc = "Code action";
      }
      {
        mode = "n";
        key = "<leader>lr";
        lspBufAction = "rename";
        options.desc = "Rename symbol";
      }
    ];
  };

  keymaps = [
    {
      mode = ["n" "x"];
      key = "<leader>lf";
      action.__raw = "function() require('conform').format({ async = true, lsp_format = 'fallback' }) end";
      options.desc = "Format buffer/selection";
    }
    {
      mode = "n";
      key = "<leader>li";
      action = "<cmd>checkhealth vim.lsp<CR>";
      options.desc = "LSP info";
    }
    {
      mode = "n";
      key = "<leader>lR";
      action = "<cmd>lsp restart<CR>";
      options.desc = "Restart LSP";
    }
    {
      mode = "n";
      key = "<leader>uf";
      action.__raw = ''
        function()
          vim.g.disable_autoformat = not vim.g.disable_autoformat
          vim.notify("Format on save (global): " .. (vim.g.disable_autoformat and "off" or "on"))
        end
      '';
      options.desc = "Toggle format on save (global)";
    }
    {
      mode = "n";
      key = "<leader>uF";
      action.__raw = ''
        function()
          vim.b.disable_autoformat = not vim.b.disable_autoformat
          vim.notify("Format on save (buffer): " .. (vim.b.disable_autoformat and "off" or "on"))
        end
      '';
      options.desc = "Toggle format on save (buffer)";
    }
    {
      mode = "n";
      key = "<leader>uh";
      action.__raw = "function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end";
      options.desc = "Toggle inlay hints";
    }
    {
      mode = "n";
      key = "<leader>ud";
      action.__raw = "function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end";
      options.desc = "Toggle diagnostics";
    }
    {
      mode = "n";
      key = "<leader>ul";
      action.__raw = ''
        function()
          local lines = not vim.diagnostic.config().virtual_lines
          vim.diagnostic.config({ virtual_lines = lines, virtual_text = not lines })
        end
      '';
      options.desc = "Toggle diagnostic virtual lines";
    }
  ];

  plugins.treesitter = {
    enable = true;
    highlight.enable = true;
    indent.enable = true;
    folding.enable = true;

    grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      bash
      diff
      git_rebase
      gitcommit
      gitignore
      json
      lua
      markdown
      markdown_inline
      query
      regex
      toml
      vim
      vimdoc
      yaml
    ];
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
            ${autoformatGuard}
            if slow_format_filetypes[vim.bo[bufnr].filetype] then
              return
            end

            local function on_format(err)
              if err and err:match("timeout$") then
                slow_format_filetypes[vim.bo[bufnr].filetype] = true
              end
            end

            return { timeout_ms = 200, lsp_format = "fallback" }, on_format
           end
        '';
      format_after_save =
        # Lua
        ''
          function(bufnr)
            ${autoformatGuard}
            if not slow_format_filetypes[vim.bo[bufnr].filetype] then
              return
            end

            return { lsp_format = "fallback" }
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
}
