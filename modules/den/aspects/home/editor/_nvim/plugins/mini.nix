# nvim mini — the mini.nvim modules (statusline, starter, clue, files, sessions, …).
{
  lib,
  config,
  ...
}: let
  # mini.clue labels for every <leader> group; keep in sync with the maps' prefixes.
  leaderGroups =
    {
      b = "buffers";
      f = "find";
      g = "git";
      l = "lsp/language";
      q = "session/quit";
      t = "terminal";
      u = "toggles";
      x = "trouble";
    }
    // lib.optionalAttrs config.plugins.dap.enable {d = "debug";};

  modeKeys = modes: keys: map (mode: {inherit mode keys;}) modes;
in {
  plugins.mini = {
    enable = true;
    mockDevIcons = true;

    # mini.basics' basic mappings take gO (0.12: document symbols) and insert <C-s>
    # (0.12: signature help); put the built-ins back, keep the rest.
    luaConfig.pre = ''
      local builtin_maps = {
        n = vim.fn.maparg("gO", "n", false, true),
        i = vim.fn.maparg("<C-S>", "i", false, true),
      }
    '';
    luaConfig.post = ''
      for mode, m in pairs(builtin_maps) do
        if m.callback then
          vim.keymap.set(mode, m.lhs, m.callback, { desc = m.desc })
        end
      end
    '';

    modules = {
      ai = {};
      bufremove = {};
      move = {};
      pairs = {};
      sessions = {};
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
        triggers = lib.concatLists [
          (modeKeys ["n" "x"] "<Leader>")
          (modeKeys ["i"] "<C-x>")
          (modeKeys ["n" "x"] "g")
          (modeKeys ["n" "x"] "[")
          (modeKeys ["n" "x"] "]")
          (modeKeys ["n" "x"] "`")
          (modeKeys ["n" "x"] "\"")
          (modeKeys ["i" "c"] "<C-r>")
          (modeKeys ["n"] "<C-w>")
          (modeKeys ["n" "x"] "z")
        ];

        clues =
          map (gen: {__raw = "require('mini.clue').gen_clues.${gen}";}) [
            "builtin_completion()"
            "g()"
            "marks()"
            "registers()"
            "square_brackets()"
            "windows()"
            "z()"
          ]
          ++ lib.concatLists (lib.mapAttrsToList (key: name:
            map (c: c // {desc = "+${name}";}) (modeKeys ["n" "x"] "<Leader>${key}"))
          leaderGroups);
      };
      files = {};
      jump = {};
      cursorword = {};
      hipatterns = {
        highlighters = {
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

          hex_color.__raw = "require('mini.hipatterns').gen_highlighter.hex_color()";
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

  keymaps = let
    n = key: action: desc: {
      mode = "n";
      inherit key;
      action.__raw = action;
      options.desc = desc;
    };
  in [
    (n "<leader>e" ''
        function()
          local path = vim.api.nvim_buf_get_name(0)
          MiniFiles.open(vim.uv.fs_stat(path) and path or nil, false)
        end
      ''
      "Files (current file)")
    (n "<leader>E" "function() MiniFiles.open(vim.uv.cwd(), false) end" "Files (cwd)")

    (n "<leader>bd" "function() MiniBufremove.delete() end" "Delete buffer")
    (n "<leader>bD" "function() MiniBufremove.delete(0, true) end" "Force delete buffer")
    (n "<leader>bo" ''
        function()
          local current = vim.api.nvim_get_current_buf()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if buf ~= current and vim.bo[buf].buflisted then
              MiniBufremove.delete(buf)
            end
          end
        end
      ''
      "Delete other buffers")

    (n "<leader>qs" ''
        function()
          if vim.v.this_session ~= "" then
            return MiniSessions.write()
          end
          vim.ui.input({ prompt = "Session name: " }, function(name)
            if name and name ~= "" then
              MiniSessions.write(name)
            end
          end)
        end
      ''
      "Write session")
    (n "<leader>ql" "function() MiniSessions.select('read') end" "Load session")
  ];
}
