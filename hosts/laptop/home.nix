{
  config,
  pkgs,
  ...
}: {
  home.username = "lvdar";
  home.homeDirectory = "/home/lvdar";

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  imports = [
    ./../../modules/home-manager/git.nix
  ];

  git.enable = true;

  programs.home-manager.enable = true;
  home.stateVersion = "24.11";
}
