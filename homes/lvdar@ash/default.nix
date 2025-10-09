{
  profiles = {
    desktop.enable = true;
  };

  desktops.hyprland.enable = true;

  "3d-printing".orca-slicer.enable = true;

  cli.programs.nvim = {
    languages = {
      clang.enable = true;
      markdown = {
        enable = true;
        markview = true;
      };
      rust.enable = true;
      python.enable = true;
      typst.enable = true;
      mcrl2.enable = true;
    };
  };

  gaming = {
    launchers = {
      # geforce-now.enable = true;
      minecraft.enable = true;
      steam.enable = true;
    };
  };

  system.impermanence = {
    persist = {
      directories = [
        "nix-config"
        "nix-secrets"
        "dev"
        "school"
        "Videos"
      ];
    };
  };

  home.stateVersion = "24.11";
}
