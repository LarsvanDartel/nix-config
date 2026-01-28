{
  cosmos = {
    profiles = {
      desktop.enable = true;
    };

    cli.programs = {
      simplelogin.enable = true;
    };

    desktops.hyprland = {
      enable = true;
      animations.enable = false;
    };

    "3d" = {
      orca-slicer.enable = true;
      freecad.enable = true;
    };

    gaming = {
      launchers = {
        # geforce-now.enable = true;
        minecraft.enable = true;
        steam.enable = true;
      };
    };

    programs = {
      zathura.enable = true;
      zotero.enable = true;
    };

    system.impermanence = {
      persist = {
        directories = [
          "nix-config"
          "nix-secrets"
          "dev"
          "school"
          "Videos"
          ".config/Code"
        ];
      };
    };
  };

  home.stateVersion = "24.11";
}
