{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.modules) mkForce;
in {
  imports = [
    # Hardware
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia

    # Disk layout
    inputs.disko.nixosModules.disko
    (import ./disko.nix {device = "/dev/nvme0n1";})
  ];

  config = {
    # Hibernate
    boot = {
      kernelParams = [
        "resume_offset=533760"
      ];
      resumeDevice = "/dev/disk/by-uuid/c2dc9bb7-f815-4c9c-bd96-68bebb100aef";
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
    boot.extraModprobeConfig = ''
      options iwlwifi power_save=0 uapsd_disable=1
      options iwlmvm power_scheme=1
    '';

    cosmos = {
      profiles = {
        desktop = {
          enable = true;
          addons = {
            hyprland.enable = true;
            greetd.tuigreet.enable = true;
          };
        };
        gaming.enable = true;
      };

      system = {
        impermanence = {
          enable = true;
          device = "/dev/mapper/crypted";
        };

        boot.detect-windows = true;
      };

      networking = {
        nameservers = mkForce [];
        # dnscrypt.enable = true;
      };

      virtualisation.containers.enable = true;

      services.suwayomi = {
        enable = true;
        basicAuth.enable = true;
        webview.enable = true;
        downloadsDir = "/var/lib/suwayomi-downloads";
        homeLink = "/home/${config.cosmos.user.name}/manga";
      };

      hardware.fingerprint.enable = true;

      # Virtual camera target for OBS (Start Virtual Camera). Shares the
      # v4l2loopback module with DroidCam so they don't fight over the kernel
      # module. Both DroidCam and OBS greedily grab the lowest-numbered free
      # loopback, so DroidCam owns video1 and OBS lands on video2.
      hardware.v4l2loopback.devices = [
        {
          number = 1;
          label = "OBS Virtual Camera";
        }
      ];

      cli.programs.nh = {
        flake-dir = "/home/${config.cosmos.user.name}/nix-config";
      };
    };

    networking.firewall.allowedUDPPorts = [25565];
    networking.firewall.allowedTCPPorts = [25565];

    system.stateVersion = "24.11";
  };
}
