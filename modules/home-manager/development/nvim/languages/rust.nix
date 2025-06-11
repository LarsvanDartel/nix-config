{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim.languages.rust;
in {
  options.modules.development.nvim.languages.rust = {
    enable = lib.mkEnableOption "rust";
  };
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim.languages.rust = {
      enable = true;
      crates = {
        enable = true;
        codeActions = true;
      };
      dap.enable = true;
      format.enable = true;
      lsp = {
        enable = true;
        opts = ''
          ['rust-analyzer'] = {
            cargo = {
              allFeatures = true,
              loadOutDirsFromCheck = true,
              buildScripts = { enable = true, },
            },
            checkOnSave = true,
            diagnostics = { enable = true, },
            procMacro = {
              enable = true,
              ignored = {
                ["async-trait"] = { "async_trait" },
                ["napi-derive"] = { "napi" },
                ["async-recursion"] = { "async_recursion" },
              },
            },
          },
        '';
      };
      treesitter.enable = true;
    };
  };
}
