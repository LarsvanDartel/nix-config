# pioneer — Raspberry Pi 3 (aarch64) server publishing endeavour's iDRAC.
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
    # Copying a closure to the SD card takes far longer than the rest of the
    # fleet's deploy: `deploy .#pioneer` on its own, and out of DeployBehind.
    deployByDefault = false;

    # The 16G SD card has no room for these, and each is an emulated aarch64 build; see docs/src/hosts.md#pioneer.
    excludes = with den.aspects; [
      core.yubikey
      home.nvim
      home.git
      home.bat
      home.btop
      home.direnv
      home.eza
      home.fd
      home.lazygit
      home.ripgrep
      home.yazi
      home.zoxide
      home.tmux
      home.misc-cli
      home."oh-my-posh"
    ];
  };

  den.aspects.pioneer = {
    includes = with den.aspects; [
      services.netbird.client
      # Not on endeavour: management proxied by the machine it recovers is not out-of-band.
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

          cosmos.services.idrac = {
            address = "192.168.2.111";
            domain = idracDomain;
            certificate = "lvdar.nl";
          };

          # 16G SD card: every write shortens its life.
          cosmos.system.journald.maxUse = "128M";

          # Fleet defaults exceed this card's free space: GC would run
          # continuously and never reach target. Shorten the horizon instead.
          cosmos.system.nix = {
            gcOlderThan = "14d";
            minFree = 256 * 1024 * 1024;
            maxFree = 1024 * 1024 * 1024;
          };

          # facter enables all of linux-firmware (825M); this board needs only the Broadcom wireless
          # firmware, which nixos-hardware's raspberry-pi-3 adds (Ethernet is the firmware-free smsc95xx).
          hardware.enableRedistributableFirmware = lib.mkForce false;

          # Deployed with deploy-rs, never rebuilt in place: nixos-rebuild-ng
          # is what pulls python into the closure.
          system.disableInstallerTools = true;

          # A fresh nixpkgs source (~200M) per lock update otherwise; `nix
          # shell nixpkgs#…` here falls back to the global registry.
          nixpkgs.flake.setFlakeRegistry = false;
          nixpkgs.flake.setNixPath = false;

          # The vendor kernel is not in the binary cache; mainline is, and supports bcm2837 headless.
          boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

          # Don't pin hardware.deviceTree.name: the board boots on the firmware's runtime-patched DTB
          # (memory, MAC, overlays), which a static store DTB would lose.
        })
      ];

      # Pi 3: parsing ~250 profiles each boot is too slow.
      cosmos.security.apparmor.coverage = "daemons";

      # Not disko: partitioned by the aarch64 SD-image installer.
      fileSystems."/" = {
        device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
        fsType = "ext4";
      };
      swapDevices = [];

      system.stateVersion = "24.11";
    };
  };
}
