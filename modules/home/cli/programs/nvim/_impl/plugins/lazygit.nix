{
  programs.nixvim = {
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
  };
}
