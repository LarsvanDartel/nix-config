# desktop.power — upower (noctalia's Battery widget hides itself without it)
# and power-profiles-daemon.
{...}: {
  den.aspects.desktop.power.nixos = {...}: {
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
  };
}
