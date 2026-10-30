# pioneer (Raspberry Pi 3, aarch64 server). den-produced.
#
# Hardware from a nixos-facter report. Generate on pioneer:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/pioneer.facter.json
{
  den,
  inputs,
  ...
}: let
  idracDomain = "idrac.lvdar.nl";
in {
  den.hosts.aarch64-linux.pioneer = {
    users.nixos = {};
    meshAddress = "100.68.78.148";
    server = true;
    sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC2O35MjlmLu5JfDRV7zNzG7BrZt3lB1ttIhRZWLjCtD";
  };

  den.aspects.pioneer = {
    includes = with den.aspects; [
      services.netbird.client
      # Not on endeavour: management proxied by the machine it recovers is
      # not out-of-band (2026-08-28: seven-hour outage).
      services.idrac
    ];

    # Mesh-only (not in public DNS): the unbound resolvers answer it with
    # this host's mesh address.
    mesh-dns-record = {host, ...}: {${idracDomain} = host.meshAddress;};

    nixos = {...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/pioneer.facter.json;}
        inputs.nixos-hardware.nixosModules.raspberry-pi-3

        # Must sit inside `imports`, not the aspect body: den forcing
        # mkForce/mkDefault early causes infinite recursion with facter.
        ({
          lib,
          pkgs,
          ...
        }: {
          # roles.server's default is too aggressive for the Pi 3: the SD card
          # can stall long enough under IO for the watchdog to reset the board.
          systemd.settings.Manager.RuntimeWatchdogSec = lib.mkForce "60s";

          # Served to mesh peers; see mesh-dns-record above.
          cosmos.services.idrac = {
            address = "192.168.2.111";
            domain = idracDomain;
            certificate = "lvdar.nl";
          };

          # 16G SD card, ~89% full; every write shortens its life.
          cosmos.system.journald.maxUse = "128M";

          # Fleet defaults exceed this card's free space: GC would run
          # continuously and never reach target. Shorten the horizon instead.
          cosmos.system.nix = {
            gcOlderThan = "14d";
            minFree = 256 * 1024 * 1024;
            maxFree = 1024 * 1024 * 1024;
          };

          # Vendor kernel isn't cached (every deploy compiled one); mainline
          # is, and supports bcm2837 headless.
          boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

          # Don't pin hardware.deviceTree.name: the board boots on the
          # firmware's runtime-patched DTB (memory, MAC, overlays); a static
          # store DTB would lose those fixups.
        })
      ];

      # Predates disko: partitioned by the aarch64 SD-image installer.
      fileSystems."/" = {
        device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
        fsType = "ext4";
      };
      swapDevices = [];

      system.stateVersion = "24.11";
    };
  };
}
