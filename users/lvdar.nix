{
  pkgs,
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
  ];

  config = {
    home.username = "lvdar";
    home.homeDirectory = "/home/lvdar";

    home.sessionVariables = {
      EDITOR = "nvim";
    };

    home.persistence."/persist/home/lvdar" = {
      directories = [
        "nixos-config"
      ];
      files = [];
      allowOther = true;
    };

    git = {
      enable = true;
      user = "LarsvanDartel";
      email = "larsvandartel73@gmail.com";
    };

    alacritty.enable = true;
    hyprland.enable = true;
    nvim.enable = true;
    # zen.enable = true;
    zsh.enable = true;

    home.stateVersion = "24.11";
    programs.home-manager.enable = true;
  };
}
