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
      services.netbird.client
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
        ({
          lib,
          pkgs,
          ...
        }: {
          # roles.server's default is too aggressive for the Pi 3: the SD card
          # can stall long enough under IO for the watchdog to reset the board.
          systemd.settings.Manager.RuntimeWatchdogSec = lib.mkForce "60s";

          # 16G SD card sitting at 89% full, of which the journal was 575M. The
          # default 10% rule is doubly wrong here: the card is small, and every
          # write shortens its life.
          cosmos.system.journald.maxUse = "128M";

          # nixos-hardware defaults this host to the Raspberry Pi Foundation's
          # vendor kernel, which nothing caches — so every deploy meant
          # compiling a kernel, either on a 1 GB Pi 3 or here under qemu. The
          # mainline aarch64 kernel is in cache.nixos.org and supports bcm2837
          # fine for a headless server; the vendor tree's advantage is
          # VideoCore, camera and other bits this host does not use.
          boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

          # Device-tree handling is deliberately left exactly as it was.
          #
          # Both kernels are plain buildLinux calls, so on aarch64 both file
          # their DTBs under dtbs/broadcom/. u-boot's FDTDIR lookup builds
          # "$fdtdir/$fdtfile" and does not descend, so it has never matched
          # anything here — this board already boots on the DTB the Pi firmware
          # hands up, which start.elf patches at runtime with the memory size,
          # the MAC address and any config.txt overlays.
          #
          # Pinning hardware.deviceTree.name would make extlinux emit an
          # explicit FDT line and load a static DTB from the store instead,
          # losing those fixups. That is a change to a working boot path, so it
          # is not made: only the kernel package differs.
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
