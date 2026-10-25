# nvim lazygit — lazygit in a float on <leader>gg.
{
  plugins.lazygit = {
    enable = true;
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>gg";
      action.__raw = ''function() vim.cmd("LazyGit") end'';
    }
  ];
}
