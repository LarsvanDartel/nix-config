# nvim performance — lua loader, plugin combining and byte-compilation.
{
  luaLoader.enable = true;

  performance = {
    combinePlugins = {
      enable = true;
      standalonePlugins = [
        "nvim-treesitter"
      ];
    };
    byteCompileLua.enable = true;
  };
}
