# nvim harpoon — file marks and their keymaps.
{
  plugins.harpoon = {
    enable = true;
    enableTelescope = true;
  };

  keymaps =
    map ({
      key,
      fn,
      desc,
    }: {
      mode = "n";
      inherit key;
      action.__raw = "function() require'harpoon'${fn} end";
      options.desc = desc;
    }) [
      {
        key = "<leader>a";
        fn = ":list():add()";
        desc = "Harpoon add file";
      }
      {
        key = "<C-e>";
        fn = ".ui:toggle_quick_menu(require'harpoon':list())";
        desc = "Harpoon menu";
      }
      {
        key = "<C-h>";
        fn = ":list():select(1)";
        desc = "Harpoon file 1";
      }
      {
        key = "<C-t>";
        fn = ":list():select(2)";
        desc = "Harpoon file 2";
      }
      {
        key = "<C-n>";
        fn = ":list():select(3)";
        desc = "Harpoon file 3";
      }
      {
        key = "<C-s>";
        fn = ":list():select(4)";
        desc = "Harpoon file 4";
      }
      {
        key = "<C-S-P>";
        fn = ":list():prev()";
        desc = "Harpoon previous";
      }
      {
        key = "<C-S-N>";
        fn = ":list():next()";
        desc = "Harpoon next";
      }
    ];
}
