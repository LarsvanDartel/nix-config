# desktop.xdg-portal
{...}: {
  den.aspects.desktop.xdg-portal.nixos = {pkgs, ...}: {
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
    };
  };
}
