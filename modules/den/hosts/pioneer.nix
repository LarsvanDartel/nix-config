# pioneer (Raspberry Pi 3, aarch64 server). den-produced; named `pioneer`
# during the migration to avoid colliding with the old `pioneer`.
#
# Hardware from a nixos-facter report. Generate on pioneer:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/pioneer.facter.json
#
{
  den,
  inputs,
  ...
}: {
  den.hosts.aarch64-linux.pioneer.users.nixos = {};

  den.aspects.pioneer = {
    includes = with den.aspects; [
      roles.server
      services.pangolin.newt
    ];

    nixos = {...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/pioneer.facter.json;}
        inputs.nixos-hardware.nixosModules.raspberry-pi-3

        # A `mkForce`/`mkDefault` wrapper must not sit directly in an aspect
        # body next to facter. den classifies aspect content by unwrapping those
        # priority wrappers, which forces the surrounding definition early —
        # early enough that facter's `mkIf config.boot.initrd.network.enable`
        # is read before the config it depends on exists. That is the infinite
        # recursion this host used to work around by avoiding facter entirely.
        # Inside `imports` the value is an opaque module to den, and is only
        # ever forced by the NixOS module system, at the right time.
        ({lib, ...}: {
          # roles.server's default is too aggressive for the Pi 3: the SD card
          # can stall long enough under IO for the watchdog to reset the board.
          systemd.settings.Manager.RuntimeWatchdogSec = lib.mkForce "60s";
        })
      ];

      # facter reports hardware, not filesystems, and pioneer predates disko:
      # the SD card was partitioned by the aarch64 SD-image installer.
      fileSystems."/" = {
        device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
        fsType = "ext4";
      };
      swapDevices = [];

      system.stateVersion = "24.11";
    };
  };
}
