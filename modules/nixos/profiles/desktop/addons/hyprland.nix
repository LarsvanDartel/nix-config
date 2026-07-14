{config, ...}: let
  m = config.flake.modules.nixos;
in {
  flake.modules.nixos.hyprland = {...}: {
    imports = with m; [greetd xdg-portal];

    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = true;
    };
  };
}
