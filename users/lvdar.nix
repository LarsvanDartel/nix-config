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
      git = {
        enable = true;
        user = "LarsvanDartel";
        email = "larsvandartel73@gmail.com";
      };
      firefox.enable = true;
      hyprland.enable = true;
      nvim.enable = true;
      ssh.enable = true;
      persist = {
        enable = true;
        directories = [
          "nixos-config"
        ];
      };
      # zen.enable = true;
      zsh.enable = true;
    };

    home.stateVersion = "24.11";
    programs.home-manager.enable = true;
  };
}
