{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.nvim.languages.rust;
in {
  options.cli.programs.nvim.languages.rust = {
    enable = mkEnableOption "rust";
  };
  config = mkIf cfg.enable {
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
