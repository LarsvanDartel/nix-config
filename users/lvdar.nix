{
  pkgs,
  config,
  inputs,
  ...
}: {
  config = {
    home.username = "lvdar";
    home.homeDirectory = "/home/lvdar";

    modules = {
      alacritty.enable = true;
      discord.enable = true;
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
      nvim.enable = true;
      signal = {
        enable = true;
        autostart = true;
      };
      spotify.enable = true;
      ssh.enable = true;
      persist = {
        enable = true;
        directories = [
          "nixos-config"
        ];
      };
      unfree.enable = true;
      # zen.enable = true;
      zsh.enable = true;
      yubico.enable = false;
    };

    home.stateVersion = "24.11";
    programs.home-manager.enable = true;
  };
}
