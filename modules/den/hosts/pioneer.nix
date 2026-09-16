# pioneer (Raspberry Pi 3, aarch64 server). den-produced.
#
# Hardware from a nixos-facter report. Generate on pioneer:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/pioneer.facter.json
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
      # The BMC's only route in. On this host because it shares nothing with
      # endeavour but a switch: management proxied by the machine it exists
      # to recover is not out-of-band (2026-08-28: seven-hour outage).
      services.idrac
    ];

    nixos = {...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/pioneer.facter.json;}
        inputs.nixos-hardware.nixosModules.raspberry-pi-3

        # Must sit inside `imports`, not the aspect body: den unwraps
        # mkForce/mkDefault wrappers to classify content, which forces the
        # definition before facter's mkIf dependencies exist — the infinite
        # recursion this host once worked around by avoiding facter entirely.
        # As an import it is opaque to den, forced at the right time.
        ({
          lib,
          pkgs,
          ...
        }: {
          # roles.server's default is too aggressive for the Pi 3: the SD card
          # can stall long enough under IO for the watchdog to reset the board.
          systemd.settings.Manager.RuntimeWatchdogSec = lib.mkForce "60s";

          # The BMC this host publishes. DHCP reservation on the home LAN;
          # the name is served to mesh peers by the unbound hosts — their
          # localRecords must point at this host's mesh address.
          cosmos.services.idrac = {
            address = "192.168.2.111";
            domain = "idrac.lvdar.nl";
            certificate = "lvdar.nl";
          };

          # 16G SD card at 89% full, and every write shortens its life —
          # the default 10% rule is doubly wrong here.
          cosmos.system.journald.maxUse = "128M";

          # Fleet defaults (min-free 1 GiB, max-free 5 GiB) are most of /
          # more than this card has ever had — the daemon would collect
          # continuously and never reach its target (the failure mode
          # core/nix.nix's option description warns about). A Pi's closure is
          # simply large relative to its card, so GC buys less than the
          # numbers suggest and every deletion is a flash write: shorten the
          # horizon, don't raise the cadence.
          cosmos.system.nix = {
            gcOlderThan = "14d";
            minFree = 256 * 1024 * 1024;
            maxFree = 1024 * 1024 * 1024;
          };

          # The vendor kernel nothing caches — every deploy compiled a
          # kernel, on a 1 GB Pi 3 or here under qemu. Mainline is in
          # cache.nixos.org and supports bcm2837 fine headless; the vendor
          # tree's edge is VideoCore and camera, unused here.
          boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

          # Device-tree handling deliberately untouched. u-boot's FDTDIR
          # lookup does not descend into dtbs/broadcom/, so it has never
          # matched anything here — this board boots on the DTB the Pi
          # firmware hands up, which start.elf patches at runtime (memory
          # size, MAC, overlays). Pinning hardware.deviceTree.name would
          # load a static DTB from the store and lose those fixups; only
          # the kernel package differs.
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
