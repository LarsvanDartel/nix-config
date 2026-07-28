# voyager (x86_64 desktop/gaming laptop, ThinkPad P1 gen3 + nvidia). den-produced;
# named `voyagerd` during the migration to avoid colliding with the old `voyager`.
#
# Hardware from a nixos-facter report; filesystems from disko. Generate on voyager:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/voyager.facter.json
#
# TODO (deferred until their aspects are converted): roles.desktop, roles.gaming,
# hyprland, tuigreet, impermanence, containers, suwayomi, fingerprint,
# v4l2loopback, nh.flake-dir, and the lvdar desktop home (hyprland/steam/obs/
# proton/nvim-languages/…). This scaffold carries only the baseline + the
# host-specific hardware so the facter report can be validated.
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.voyagerd = {
    hostName = "voyager";
    users.lvdar = {};
  };

  den.aspects.voyagerd = {
    includes = with den.aspects; [
      core.boot
      roles.desktop
      desktop.hyprland
    ];

    # the primary user gets the desktop home environment on this host.
    lvdar.includes = [den.aspects.roles.desktop-home];

    nixos = {...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/voyager.facter.json;}
        inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.disko.nixosModules.disko
        (import ../../hosts/voyager/_hw/disko.nix {device = "/dev/nvme0n1";})
      ];

      cosmos.system.boot.detect-windows = true;

      # Hibernate
      boot = {
        kernelParams = ["resume_offset=533760"];
        resumeDevice = "/dev/disk/by-uuid/c2dc9bb7-f815-4c9c-bd96-68bebb100aef";
        extraModprobeConfig = ''
          options iwlwifi power_save=0 uapsd_disable=1
          options iwlmvm power_scheme=1

          # NuPhy Air75 registers as an Apple keyboard; fnmode=0 makes the top row
          # act as plain F1-F12 without needing Fn, fixing Fn key combos.
          options hid_apple fnmode=0
        '';
      };

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

      networking.networkmanager.wifi.powersave = false;
      environment.etc."NetworkManager/conf.d/wifi.conf".text = ''
        [connection]
        wifi.powersave = 2

        [device]
        wifi.scan-rand-mac-address = no
      '';
      networking.wireless.extraConfig = ''
        bgscan=""
      '';

      networking.firewall.allowedUDPPorts = [25565];
      networking.firewall.allowedTCPPorts = [25565];

      system.stateVersion = "24.11";
    };
  };
}
