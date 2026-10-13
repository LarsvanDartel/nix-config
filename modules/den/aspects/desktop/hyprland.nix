# desktop.hyprland — the compositor + its portal/greeter deps; its home half
# (home.hyprland) goes to every user via to-users.
{den, ...}: {
  den.aspects.desktop.hyprland = {
    provides.to-users.includes = [den.aspects.home.hyprland];

    includes = with den.aspects.desktop; [
      greetd
      xdg-portal
    ];
    nixos = {
      config,
      lib,
      ...
    }: {
      environment.sessionVariables.NIXOS_OZONE_WL = "1";

      programs.hyprland = {
        enable = true;
        xwayland.enable = true;
        withUWSM = true;
      };

      # Only the uwsm entry (withUWSM also installs a plain one → duplicate
      # rows); gated so a specialisation disabling Hyprland drops it.
      cosmos.profiles.desktop.addons.greetd.sessions = lib.optional config.programs.hyprland.enable {
        name = "hyprland.desktop";
        path = "${config.programs.hyprland.package}/share/wayland-sessions/hyprland-uwsm.desktop";
      };

      cosmos.profiles.desktop.lockCommand = lib.mkIf config.programs.hyprland.enable "hyprlock";
    };
  };
}
