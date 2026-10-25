# nvim terminal — one reusable bottom-split :terminal on <leader>tt.
{
  keymaps = [
    {
      mode = "n";
      key = "<leader>tt";
      action.__raw = ''
        (function()
          local buf, win

          return function()
            if win and vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_win_hide(win)
              win = nil
              return
            end

            vim.cmd("botright 15split")
            win = vim.api.nvim_get_current_win()
            if buf and vim.api.nvim_buf_is_valid(buf) then
              vim.api.nvim_win_set_buf(win, buf)
            else
              vim.cmd.terminal()
              buf = vim.api.nvim_get_current_buf()
              vim.bo[buf].buflisted = false
              -- A dead shell must not be toggled back in; start a fresh one next time.
              vim.api.nvim_create_autocmd("TermClose", {
                buffer = buf,
                once = true,
                callback = function(args)
                  vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(args.buf) then
                      vim.api.nvim_buf_delete(args.buf, { force = true })
                    end
                  end)
                end,
              })
            end
            vim.cmd.startinsert()
          end
        end)()
      '';
      options.desc = "Toggle terminal";
    }
    {
      mode = "t";
      key = "<Esc><Esc>";
      action = "<C-\\><C-n>";
      options.desc = "Exit terminal mode";
    }
  ];
}
