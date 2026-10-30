# voyager on the ThinkPad P1 gen3 (nvidia) — hardware profile; selected in hosts/voyager.nix. Delete after the move to the Framework 12.
{inputs}: {...}: {
  imports = [
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia
  ];

  cosmos.system.boot.detect-windows = true;

  # Keep nvidia (103 MB GSP firmware) out of the initrd: three copies
  # filled the 511 MB ESP. nvidia loads at stage 2.
  facter.detected.boot.graphics.kernelModules = ["i915"];

  hardware.nvidia = {
    open = true;
    powerManagement = {
      enable = true;
      finegrained = true;
    };
    prime.offload = {
      enable = true;
      enableOffloadCmd = true;
    };
  };

  home-manager.users.lvdar.cosmos.programs.obs-studio.cudaSupport = true;
}
