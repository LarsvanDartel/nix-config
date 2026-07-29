# desktop.power — the battery/power daemons the shells read through.
#
# noctalia's Battery widget (and its low-battery toast) talks to UPower over
# D-Bus rather than reading /sys directly, so without upower it reports "no
# battery detected" and hides itself entirely — that is the whole reason the
# widget was missing, not a bar-config problem. power-profiles-daemon backs the
# PowerProfile control-centre toggle and the performance/balanced/saver switch.
{...}: {
  den.aspects.desktop.power.nixos = {...}: {
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
  };
}
