{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
    ./../../modules/home-manager/git.nix
  ];

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
  git.enable = true;

  programs.home-manager.enable = true;
  home.stateVersion = "24.11";
}
