# desktop.hyprland (nixos side) — the compositor + its portal/greeter deps.
{den, ...}: {
  den.aspects.desktop.hyprland = {
    includes = with den.aspects.desktop; [
      greetd
      xdg-portal
    ];
    nixos = {...}: {
      environment.sessionVariables.NIXOS_OZONE_WL = "1";

      programs.hyprland = {
        enable = true;
        xwayland.enable = true;
        withUWSM = true;
      };
    };
  };
}
