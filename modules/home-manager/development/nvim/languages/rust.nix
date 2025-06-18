{
  config,
  lib,
  pkgs,
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
      format = {
        enable = true;
        # Use rustfmt on path
        package = pkgs.writeShellApplication {
          name = "rustfmt";
          text = ''
            rustfmt "$@"
          '';
        };
      };
      lsp = {
        enable = true;
        # Use rust-analyzer on path
        package = ["rust-analyzer"];
        opts = ''
          ['rust-analyzer'] = {
            cargo = {
              allFeatures = true,
              loadOutDirsFromCheck = true,
              buildScripts = { enable = true, },
            },
            checkOnSave = true,
            diagnostics = { enable = true, },
            procMacro = { enable = true, },
          },
        '';
      };
      treesitter.enable = true;
    };
  };
}
