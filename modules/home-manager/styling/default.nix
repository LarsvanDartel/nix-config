{pkgs, ...}: {
  imports = [
    ./fonts
    ./themes
  ];

  config = {
    stylix = {
      enable = true;
      autoEnable = true;
      opacity.terminal = 0.6;

      # TODO: Move to cursor module
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 22;
      };
    };
  };
}
