{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim;
in {
  imports = [
    ./languages
  ];

  options.modules.development.nvim = {
    enable = lib.mkEnableOption "nvim";
  };

  config = lib.mkIf cfg.enable {
    stylix.targets.nvf.enable = true;

    home.sessionVariables = {
      EDITOR = "nvim";
    };

    modules.persist.directories = [".config/github-copilot"];

    programs.nvf = {
      enable = true;
      settings = {
        vim = {
          viAlias = true;
          vimAlias = true;
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
          };

          treesitter = {
            enable = true;
            highlight.enable = true;
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

          visuals = {
            nvim-web-devicons.enable = true;
            nvim-cursorline.enable = true;
            fidget-nvim.enable = true;
            highlight-undo.enable = true;
            indent-blankline.enable = true;
          };

          theme.transparent = true;

          assistant.copilot = {
            enable = true;
            cmp.enable = true;
          };

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
