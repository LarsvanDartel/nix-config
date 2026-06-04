{pkgs, ...}: {
  cosmos = {
    profiles = {
      desktop.enable = true;
    };

    cli.programs = {
      simplelogin.enable = true;
      claude.enable = true;
      pangolin.enable = true;
      tmux = {
        plugins.which-key.enable = true;
      };
      taskwarrior.enable = true;
      nvim = {
        languages = {
          rust.enable = true;
          clang.enable = true;
          typst.enable = true;
          python.enable = true;
          rocq.enable = true;
          formal.enable = true;
          mcrl2.enable = true;
        };
      };
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
        minecraft = {
          enable = true;
          mcsr.enable = true;
        };
        steam.enable = true;
      };
    };

    programs = {
      zathura = {
        enable = true;
        defaultApplication = true;
      };
      libreoffice.enable = true;
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
          "balatro"
        ];
      };
    };
  };

  programs.ssh.settings = {
    "es-pynq047.ics.ele.tue.nl" = {
      setEnv = "TERM=xterm-256color";
    };
  };

  home.packages = [pkgs.mcrl2];

  home.stateVersion = "24.11";
}
