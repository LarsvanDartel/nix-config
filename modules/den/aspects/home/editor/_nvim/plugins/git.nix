# nvim git — gitsigns (signs, hunks, blame), lazygit and the <leader>g maps.
# mini.statusline's diff section reads gitsigns' b:gitsigns_status.
{
  plugins = {
    gitsigns = {
      enable = true;
      settings.signs = {
        add.text = "+";
        change.text = "~";
      };
    };

    lazygit.enable = true;

    telescope.keymaps = {
      "<leader>gc" = {
        action = "git_commits";
        options.desc = "Commits";
      };
      "<leader>gC" = {
        action = "git_bcommits";
        options.desc = "Buffer commits";
      };
    };
  };

  keymaps = let
    gs = fn: {__raw = "function() require('gitsigns').${fn} end";};
    # A visual range stages/resets just the selected lines.
    range = fn: {__raw = "function() require('gitsigns').${fn}({ vim.fn.line('.'), vim.fn.line('v') }) end";};
  in [
    {
      mode = "n";
      key = "<leader>gg";
      action = "<cmd>LazyGit<CR>";
      options.desc = "Lazygit";
    }
    {
      mode = "n";
      key = "<leader>gs";
      action = gs "stage_hunk()";
      options.desc = "Stage hunk";
    }
    {
      mode = "x";
      key = "<leader>gs";
      action = range "stage_hunk";
      options.desc = "Stage selected lines";
    }
    {
      mode = "n";
      key = "<leader>gr";
      action = gs "reset_hunk()";
      options.desc = "Reset hunk";
    }
    {
      mode = "x";
      key = "<leader>gr";
      action = range "reset_hunk";
      options.desc = "Reset selected lines";
    }
    {
      mode = "n";
      key = "<leader>gS";
      action = gs "stage_buffer()";
      options.desc = "Stage buffer";
    }
    {
      mode = "n";
      key = "<leader>gR";
      action = gs "reset_buffer()";
      options.desc = "Reset buffer";
    }
    {
      mode = "n";
      key = "<leader>gp";
      action = gs "preview_hunk()";
      options.desc = "Preview hunk";
    }
    {
      mode = "n";
      key = "<leader>gb";
      action = gs "blame_line({ full = true })";
      options.desc = "Blame line";
    }
    {
      mode = "n";
      key = "<leader>gB";
      action = gs "toggle_current_line_blame()";
      options.desc = "Toggle line blame";
    }
    {
      mode = "n";
      key = "<leader>gd";
      action = gs "diffthis()";
      options.desc = "Diff against index";
    }
    {
      mode = "n";
      key = "]h";
      action = gs "nav_hunk('next')";
      options.desc = "Next hunk";
    }
    {
      mode = "n";
      key = "[h";
      action = gs "nav_hunk('prev')";
      options.desc = "Previous hunk";
    }
    {
      mode = ["o" "x"];
      key = "ih";
      action = gs "select_hunk()";
      options.desc = "Inside hunk";
    }
  ];
}
