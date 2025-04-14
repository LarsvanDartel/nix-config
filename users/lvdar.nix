{config, ...}: {
  home = {
    username = "lvdar";
    homeDirectory = "/home/lvdar";
    stateVersion = "24.11";
  };

  modules = {
    "3d-printing".orca-slicer.enable = true;
    bluetuith.enable = true;
    development = {
      direnv.enable = true;
      nvim.enable = true;
    };
    discord = {
      enable = true;
      autostart = true;
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
    firefox.enable = true;
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
    persist = {
      enable = true;
      directories = [
        "nixos-config"
      ];
    };
    unfree.enable = true;
    # zen.enable = true;
    yubico.enable = false;
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
  };

  programs.home-manager.enable = true;
}
