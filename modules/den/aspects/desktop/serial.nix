# desktop.serial — dialout access for USB-serial flashing tools and browser Web Serial.
{...}: {
  den.aspects.desktop.serial.nixos = {...}: {
    cosmos.user.extraGroups = ["dialout"];
  };
}
