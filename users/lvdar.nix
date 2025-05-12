{
  config,
  pkgs,
  ...
}: {
  home = {
    username = "lvdar";
    homeDirectory = "/home/lvdar";
    stateVersion = "24.11";
  };

  modules = {
    "3d-printing".orca-slicer.enable = true;
    bluetuith.enable = true;
    btop.enable = true;
    development = {
      direnv.enable = true;
      nvim = {
        enable = true;
        languages = {
          clang.enable = true;
          markdown.enable = true;
          python.enable = true;
          tex.enable = true;
          ts.enable = true;
          vue.enable = true;
        };
      };
    };
    discord = {
      enable = true;
      autostart = true;
    };
    gaming = {
      enable = true;
      launchers = {
        steam.enable = true;
        minecraft.enable = true;
      };
    };
    git = {
      enable = true;
      user = "LarsvanDartel";
      email = "larsvandartel73@gmail.com";
    };
    graphical = {
      hyprland.enable = true;
      rofi.rofi-rbw = {
        enable = true;
        email = "larsvandartel@proton.me";
        base_url = "https://api.bitwarden.eu";
        identity_url = "https://identity.bitwarden.eu";
      };
    };
    keyring.enable = true;
    libre-office.enable = true;
    firefox.enable = true;
    persist = {
      enable = true;
      directories = [
        "nixos-config"
        "dev"
        "school"
      ];
    };
    pulsemixer.enable = true;
    shell = {
      zsh.enable = true;
      prompt.oh-my-posh.enable = true;
    };
    signal = {
      enable = true;
      autostart = true;
    };
    spotify.enable = true;
    ssh.enable = true;
    terminal.foot.enable = true;
    vpn.eduvpn.enable = true;
    unfree.enable = true;
    # zen.enable = true;
    yubico.enable = false;
    zathura.enable = true;
  };

  modules.styling = let
    fontpkgs = config.modules.styling.fonts.pkgs;
  in {
    fonts = {
      serif = fontpkgs."DejaVu Serif";
      sansSerif = fontpkgs."DejaVu Sans";
      monospace = fontpkgs."Cozette";
      emoji = fontpkgs."Noto Color Emoji";
      interface = fontpkgs."Cozette";
      extraFonts = [];
    };
    theme.nord = {
      enable = true;
      darkMode = true;
    };
    wallpaper = {
      src = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/dharmx/walls/6bf4d733ebf2b484a37c17d742eb47e5139e6a14/digital/a_group_of_birds_flying_in_the_sky.jpg";
        hash = "sha256-v6KVInk5JJZPLkOAfC8yuDQtnZtT1DWQI7u6UfG59WY=";
      };
      themed = true;
    };
  };

  programs.home-manager.enable = true;
}
