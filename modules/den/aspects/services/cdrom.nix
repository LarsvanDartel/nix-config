# services.cdrom
{...}: {
  den.aspects.services.cdrom.nixos = {...}: {
    cosmos.user.extraGroups = ["cdrom"];
    boot.kernelModules = ["sg" "sr_mod" "cdrom"];
    services.udev.extraRules = ''
      KERNEL=="sr[0-9]*", GROUP="cdrom", MODE="0660"
    '';
  };
}
