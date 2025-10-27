{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.cosmos) get-non-default-nix-files;
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim;
in {
  imports =
    [inputs.nvf.homeManagerModules.default]
    ++ get-non-default-nix-files ./languages;

  options.cosmos.cli.programs.nvim = {
    enable = mkEnableOption "nvim";
  };

  config = mkIf cfg.enable {
    stylix.targets.nvf.enable = true;

    home.sessionVariables = {
      EDITOR = "nvim";
    };

    cosmos.system.impermanence.persist.directories = [".config/github-copilot"];

    programs.nvf = {
      enable = true;
      settings = {
        vim = {
          viAlias = false;
          vimAlias = false;
          debugMode = {
            enable = false;
            level = 16;
            logFile = "/tmp/nvim.log";
          };

          lsp = {
            enable = true;
            formatOnSave = true;
            lightbulb.enable = true;
            trouble.enable = true;
            inlayHints.enable = true;
          };

          treesitter = {
            enable = true;
            highlight.enable = true;
            fold = true;
          };

          debugger.nvim-dap = {
            enable = true;
            ui.enable = true;
          };

          languages = {
            enableFormat = true;
            enableTreesitter = true;
            enableExtraDiagnostics = true;
          };

          mini = {
            surround.enable = true;
          };

          visuals = {
            nvim-web-devicons.enable = true;
            nvim-cursorline.enable = true;
            fidget-nvim.enable = true;
            highlight-undo.enable = true;
            indent-blankline.enable = true;
          };

          theme.transparent = true;

          # assistant.copilot = {
          #   enable = true;
          #   cmp.enable = true;
          # };

          autopairs.nvim-autopairs.enable = true;

          autocomplete.nvim-cmp.enable = true;
          snippets.luasnip.enable = true;

          filetree.neo-tree.enable = true;

          tabline.nvimBufferline.enable = true;

          binds.whichKey.enable = true;

          statusline.lualine.enable = true;

          telescope.enable = true;

          git = {
            enable = true;
            gitsigns.enable = true;
            gitsigns.codeActions.enable = false;
          };

          notify.nvim-notify.enable = true;

          notes.todo-comments.enable = true;

          terminal = {
            toggleterm = {
              enable = true;
              lazygit.enable = true;
            };
          };
        };
      };
    };
  };
}
