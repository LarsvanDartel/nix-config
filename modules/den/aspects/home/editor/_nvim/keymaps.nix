# nvim keymaps — leader and the general-purpose normal/visual maps. Feature maps
# live with their plugin; mini.clue's group labels are in plugins/mini.nix.
{lib, ...}: {
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  keymaps = let
    map = mode:
      lib.mapAttrsToList (key: {
        action,
        desc,
      }: {
        inherit mode key action;
        options.desc = desc;
      });
    normal = map "n" {
      "<esc>" = {
        action = ":noh<CR>";
        desc = "Clear search highlight";
      };

      Y = {
        action = "y$";
        desc = "Yank to end of line";
      };

      "<C-Up>" = {
        action = ":resize -2<CR>";
        desc = "Decrease window height";
      };
      "<C-Down>" = {
        action = ":resize +2<CR>";
        desc = "Increase window height";
      };
      "<C-Left>" = {
        action = ":vertical resize +2<CR>";
        desc = "Increase window width";
      };
      "<C-Right>" = {
        action = ":vertical resize -2<CR>";
        desc = "Decrease window width";
      };

      "<leader>qq" = {
        action = "<cmd>qa<CR>";
        desc = "Quit all";
      };
    };
    # x, not v: select mode belongs to snippet placeholders (<Tab> jumps there).
    visual = map "x" {
      ">" = {
        action = ">gv";
        desc = "Indent and reselect";
      };
      "<" = {
        action = "<gv";
        desc = "Dedent and reselect";
      };
      "<TAB>" = {
        action = ">gv";
        desc = "Indent and reselect";
      };
      "<S-TAB>" = {
        action = "<gv";
        desc = "Dedent and reselect";
      };
    };
  in
    lib.nixvim.keymaps.mkKeymaps {options.silent = true;} (normal ++ visual);
}
