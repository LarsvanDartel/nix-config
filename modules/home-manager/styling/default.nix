{pkgs, ...}: {
  imports = [
    ./icons
    ./fonts
    ./themes
    ./wallpaper.nix
  ];

  config = {
    stylix = {
      enable = true;
      autoEnable = true;
      opacity.terminal = 1.0;

      # TODO: Move to cursor module
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 22;
      };
    };
  };
}
