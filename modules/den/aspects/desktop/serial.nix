# desktop.serial — USB-serial access for flashing tools; the dialout group also
# covers browser Web Serial, which hits the same permission check.
{...}: {
  den.aspects.desktop.serial.nixos = {...}: {
    cosmos.user.extraGroups = ["dialout"];
  };
}
