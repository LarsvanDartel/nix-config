{
  inputs,
  config,
  ...
}: {
  imports = [
    # Hardware
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia

    # Disk layout
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  config = {
    networking.hostId = "b8433556";

    hardware = {
      nvidia = {
        modesetting.enable = true;
        open = false;
        powerManagement.enable = true;
        nvidiaPersistenced = true;

        prime = {
          intelBusId = "PCI:7@0:0:0";
          nvidiaBusId = "PCI:3@0:0:0";
        };
      };
      intelgpu = {
        driver = "xe";
        vaapiDriver = "intel-media-driver";
        enableHybridCodec = true;
      };
      graphics.enable = true;
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

    sops.secrets = {
      "keys/proton/private-key" = {};
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
        proton-vpn = {
          enable = true;
          interface.privateKeyFile = config.sops.secrets."keys/proton/private-key".path;
          endpoint = {
            publicKey = "D8Sqlj3TYwwnTkycV08HAlxcXXS3Ura4oamz8rB5ImM=";
            ip = "103.69.224.4";
          };
        };
        nginx.enable = true;
        kanidm.enable = true;
        jellyfin.enable = true;
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
