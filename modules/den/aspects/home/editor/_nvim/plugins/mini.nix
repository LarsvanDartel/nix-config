{
  programs.nixvim = {
    plugins.mini = {
      enable = true;
      mockDevIcons = true;
      modules = {
        comment = {};
        move = {};
        pairs = {};
        splitjoin = {};
        surround = {
          mappings = {
            add = "gsa";
            delete = "gsd";
            find = "gsf";
            find_left = "gsF";
            highlight = "gsh";
            replace = "gsr";
            update_n_lines = "gsn";
          };
        };
        basics = {};
        clue = {
          triggers = [
            # Leader triggers
            {
              mode = "n";
              keys = "<Leader>";
            }
            {
              mode = "x";
              keys = "<Leader>";
            }

            # Built-in completion
            {
              mode = "i";
              keys = "<C-x>";
            }

            # `g` key
            {
              mode = "n";
              keys = "g";
            }
            {
              mode = "x";
              keys = "g";
            }

            # Marks
            {
              mode = "n";
              keys = "\"";
            }
            {
              mode = "n";
              keys = "`";
            }
            {
              mode = "x";
              keys = "\"";
            }
            {
              mode = "x";
              keys = "`";
            }

            # Registers
            {
              mode = "n";
              keys = "\"";
            }
            {
              mode = "x";
              keys = "\"";
            }
            {
              mode = "i";
              keys = "<C-r>";
            }
            {
              mode = "c";
              keys = "<C-r>";
            }

            # Window commands
            {
              mode = "n";
              keys = "<C-w>";
            }

            # `z` key
            {
              mode = "n";
              keys = "z";
            }
            {
              mode = "x";
              keys = "z";
            }
          ];

          clues = [
            # Enhance this by adding descriptions for <Leader> mapping groups
            "miniclue.gen_clues.builtin_completion()"
            "miniclue.gen_clues.g()"
            "miniclue.gen_clues.marks()"
            "miniclue.gen_clues.registers()"
            "miniclue.gen_clues.windows()"
            "miniclue.gen_clues.z()"
          ];
        };
        diff = {
          view = {
            style = "sign";
          };
        };
        files = {};
        jump = {};
        cursorword = {};
        hipatterns = {
          highlighters = {
            # Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
            fixme = {
              pattern = "%f[%w]()FIXME()%f[%W]";
              group = "MiniHipatternsFixme";
            };
            hack = {
              pattern = "%f[%w]()HACK()%f[%W]";
              group = "MiniHipatternsHack";
            };
            todo = {
              pattern = "%f[%w]()TODO()%f[%W]";
              group = "MiniHipatternsTodo";
            };
            note = {
              pattern = "%f[%w]()NOTE()%f[%W]";
              group = "MiniHipatternsNote";
            };

            # Highlight hex color strings (`#rrggbb`) using that color
            hex_color = "hipatterns.gen_highlighter.hex_color()";
          };
        };
        icons = {};
        indentscope = {};
        notify = {};
        starter = {
          content_hooks = {
            "__unkeyed-1.adding_bullet" = {
              __raw = "require('mini.starter').gen_hook.adding_bullet()";
            };
            "__unkeyed-2.indexing" = {
              __raw = "require('mini.starter').gen_hook.indexing('all', { 'Builtin actions' })";
            };
            "__unkeyed-3.padding" = {
              __raw = "require('mini.starter').gen_hook.aligning('center', 'center')";
            };
          };
          evaluate_single = true;
          header = ''
            ███╗   ██╗██╗██╗  ██╗██╗   ██╗██╗███╗   ███╗
            ████╗  ██║██║╚██╗██╔╝██║   ██║██║████╗ ████║
            ██╔██╗ ██║██║ ╚███╔╝ ██║   ██║██║██╔████╔██║
            ██║╚██╗██║██║ ██╔██╗ ╚██╗ ██╔╝██║██║╚██╔╝██║
            ██║ ╚████║██║██╔╝ ██╗ ╚████╔╝ ██║██║ ╚═╝ ██║
          '';
          items = {
            "__unkeyed-1.buildtin_actions" = {
              __raw = "require('mini.starter').sections.builtin_actions()";
            };
            "__unkeyed-2.recent_files_current_directory" = {
              __raw = "require('mini.starter').sections.recent_files(10, false)";
            };
            "__unkeyed-3.recent_files" = {
              __raw = "require('mini.starter').sections.recent_files(10, true)";
            };
            "__unkeyed-4.sessions" = {
              __raw = "require('mini.starter').sections.sessions(5, true)";
            };
          };
        };
        statusline = {};
        tabline = {};
        trailspace = {};
        fuzzy = {};
      };
    };

    keymaps = [
      # {
      #   mode = "n";
      #   key = "<leader>a";
      #   action.__raw = "function() require'harpoon':list():add() end";
      # }
    ];
  };
}
