# desktop.hyprland (nixos side) — the compositor + its portal/greeter deps.
{den, ...}: {
  den.aspects.desktop.hyprland = {
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

      # Offer ONLY the uwsm-managed entry to the greeter. withUWSM also installs a
      # plain `hyprland.desktop`; listing both is what produced duplicate rows.
      # Gated on the program actually being enabled, so a specialisation that
      # turns Hyprland off (see hosts/voyager.nix) drops the entry too.
      cosmos.profiles.desktop.addons.greetd.sessions = lib.optional config.programs.hyprland.enable {
        name = "hyprland.desktop";
        path = "${config.programs.hyprland.package}/share/wayland-sessions/hyprland-uwsm.desktop";
      };

      # Same "only when this compositor is actually the active one" gating as
      # the greetd session entry above — see core.yubikey for the consumer.
      cosmos.profiles.desktop.lockCommand = lib.mkIf config.programs.hyprland.enable "hyprlock";
    };
  };
}
