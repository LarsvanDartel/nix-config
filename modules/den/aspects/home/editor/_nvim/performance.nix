# nvim performance — lua loader, plugin combining and byte-compilation.
{
  luaLoader.enable = true;

  performance = {
    combinePlugins = {
      enable = true;
      # friendly-snippets: luasnip's vscode loader can't find it inside the combined pack.
      standalonePlugins = [
        "nvim-treesitter"
        "friendly-snippets"
      ];
    };
    byteCompileLua.enable = true;
  };
}
