{inputs, ...}: {
  imports = [
    # Hardware
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime

    # Disk layout
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  config = {
    networking.hostId = "b8433556";
    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = false;
      nvidiaPersistenced = true;
      videoAcceleration = true;
    };

    boot = {
      kernelParams = [
        "nohibernate"
      ];
      supportedFilesystems = ["vfat" "zfs"];
      zfs.extraPools = ["tank"];
    };

    services.zfs = {
      autoScrub = {
        enable = true;
        interval = "*-*-1,15 02:30";
      };
      trim.enable = true;
    };

    sops.secrets."keys/zfs/tank" = {};
    systemd.services."zfs-decode-key" = {
      description = "Decode ZFS raw key from SOPS secret";
      partOf = ["zfs-import.target"];
      wantedBy = ["zfs-import.target"];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -m 0700 -d /run/keys
        base64 -d /run/secrets/keys/zfs/tank > /run/keys/zfs-tank.key
        chmod 0400 /run/keys/zfs-tank.key
      '';
      postStop = ''
        shred -u /run/keys/zfs-tank.key 2>/dev/null || rm -f /run/keys/zfs-tank.key
      '';
    };

    cosmos = {
      system = {
        impermanence = {
          enable = true;
          device = "/dev/disk/by-label/nixos";
        };
      };

      profiles = {
        server.enable = true;
      };

      services = {
        nginx.enable = true;
        kanidm.enable = true;
      };

      hardware = {
        cdrom.enable = true;
        ipmi-fancontrol = {
          enable = true;
          dynamic = true;
          minSpeed = 5;
          curve = 5.0;
          ignoreDevices = ["loc"];
          nvidia-smi = {
            enable = true;
            maxTemp = 105;
          };
        };
      };
    };

    system.stateVersion = "24.11";
  };
}
