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
      # The BMC's only route in. This host earns its place here by sharing
      # nothing with endeavour but a switch: out-of-band management proxied by
      # the machine it exists to recover is not out-of-band, which is what a
      # seven-hour outage on 2026-08-28 demonstrated.
      services.idrac
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

          # The BMC this host publishes. Its address is a DHCP reservation on
          # the home LAN, and the name is served to mesh peers by the two hosts
          # running unbound — see their localRecords, which must point at this
          # host's mesh address.
          cosmos.services.idrac = {
            address = "192.168.2.111";
            domain = "idrac.lvdar.nl";
            certificate = "lvdar.nl";
          };

          # 16G SD card sitting at 89% full, of which the journal was 575M. The
          # default 10% rule is doubly wrong here: the card is small, and every
          # write shortens its life.
          cosmos.system.journald.maxUse = "128M";

          # The fleet default min-free of 1 GiB is most of this host's 2.1 GiB
          # of free space, and max-free of 5 GiB is more free space than the
          # card has ever had — together they would mean the daemon collects
          # continuously and never reaches its target, which is the failure
          # mode core/nix.nix's option description warns about. Scaled to the
          # card instead.
          #
          # The store is 9.3G of the 12G in use here across only 11
          # generations, so unlike endeavour this host is not full *because* of
          # uncollected history — a Pi's closure is simply large relative to
          # its card. GC buys less here than the numbers suggest, and every
          # deletion is a write on flash, so the horizon is shortened rather
          # than the cadence raised.
          cosmos.system.nix = {
            gcOlderThan = "14d";
            minFree = 256 * 1024 * 1024;
            maxFree = 1024 * 1024 * 1024;
          };

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
