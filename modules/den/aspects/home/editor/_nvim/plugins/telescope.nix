# nvim telescope — fuzzy finder, its extensions and the <leader>f maps.
{
  lib,
  pkgs,
  ...
}: {
  plugins.telescope = {
    enable = true;

    extensions = {
      fzf-native.enable = true;
      # Routes vim.ui.select (code actions, session picker, …) through telescope.
      ui-select.enable = true;
    };

    keymaps =
      lib.mapAttrs (_: {
        action,
        desc,
        mode ? "n",
      }: {
        inherit action mode;
        options.desc = desc;
      }) {
        "<leader>ff" = {
          action = "find_files";
          desc = "Files";
        };
        "<leader>fg" = {
          action = "live_grep";
          desc = "Live grep";
        };
        "<leader>fw" = {
          action = "grep_string";
          desc = "Grep word/selection";
          mode = ["n" "x"];
        };
        "<leader>fb" = {
          action = "buffers";
          desc = "Buffers";
        };
        "<leader>fr" = {
          action = "oldfiles";
          desc = "Recent files";
        };
        "<leader>fh" = {
          action = "help_tags";
          desc = "Help";
        };
        "<leader>fk" = {
          action = "keymaps";
          desc = "Keymaps";
        };
        "<leader>fc" = {
          action = "commands";
          desc = "Commands";
        };
        "<leader>f/" = {
          action = "current_buffer_fuzzy_find";
          desc = "Fuzzy in buffer";
        };
        "<leader>f." = {
          action = "resume";
          desc = "Resume last picker";
        };
        "<leader>fs" = {
          action = "lsp_document_symbols";
          desc = "Document symbols";
        };
        "<leader>fS" = {
          action = "lsp_dynamic_workspace_symbols";
          desc = "Workspace symbols";
        };
        "<leader>fd" = {
          action = "diagnostics";
          desc = "Diagnostics";
        };
      };

    settings = {
      pickers.find_files.find_command = [
        (lib.getExe pkgs.fd)
        "--type"
        "f"
        "--hidden"
        "--exclude"
        ".git"
      ];
      defaults = {
        vimgrep_arguments = [
          (lib.getExe pkgs.ripgrep)
          "--color=never"
          "--no-heading"
          "--with-filename"
          "--line-number"
          "--column"
          "--smart-case"
        ];
        file_ignore_patterns = [
          "^.git/"
        ];
        layout_config = {
          prompt_position = "top";
        };
        mappings = {
          i = {
            "<A-j>" = {
              __raw = "require('telescope.actions').move_selection_next";
            };
            "<A-k>" = {
              __raw = "require('telescope.actions').move_selection_previous";
            };
          };
        };
        selection_caret = "> ";
        set_env = {
          COLORTERM = "truecolor";
        };
        sorting_strategy = "ascending";
      };
    };
  };
}
