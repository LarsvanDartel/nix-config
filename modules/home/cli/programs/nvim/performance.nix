{
  programs.nixvim = {
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
  };
}
