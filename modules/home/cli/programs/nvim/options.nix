{
  programs.nixvim = {
    globals = {
      loaded_ruby_provider = 0;
      loaded_perl_provider = 0;
      loaded_python_provider = 0;
    };

    clipboard = {
      register = "unnamedplus";

      providers.wl-copy.enable = true;
    };

    opts = {
      updatetime = 100;

      relativenumber = true;
      number = true;
      hidden = true;
      splitbelow = true;
      splitright = true;

      swapfile = false;
      modeline = true;
      modelines = 100;
      undofile = true;
      incsearch = true;
      inccommand = "split";
      ignorecase = true;
      smartcase = true;

      scrolloff = 8;
      cursorline = false;
      cursorcolumn = false;
      laststatus = 3;
      fileencoding = "utf-8";
      termguicolors = true;
      spell = false;
      wrap = false;

      tabstop = 4;
      shiftwidth = 4;
      expandtab = true;
      autoindent = true;

      textwidth = 0;
      foldlevel = 99;
    };
  };
}
