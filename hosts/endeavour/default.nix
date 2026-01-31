{
  inputs,
  config,
  pkgs,
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
      "keys/eweka" = {owner = config.cosmos.services.arr.sabnzbd.user;};
    };

    cosmos = {
      system = {
        impermanence = {
          enable = true;
          device = "/dev/disk/by-label/nixos";
          persist.directories = ["/var/lib/arr"];
        };
      };

      profiles = {
        server.enable = true;
      };

      services = {
        nginx.enable = true;
        kanidm.enable = true;
        jellyfin.enable = true;
        arr = {
          enable = true;
          stateDir = "/var/lib/arr";
          mediaDir = "/tank/media";

          transmission = {
            enable = true;
            vpn.enable = true;
          };

          sabnzbd = {
            enable = true;
            vpn.enable = true;
            secretFiles = [config.sops.secrets."keys/eweka".path];
            extraSettings.servers = {
              eweka = {
                displayname = "Eweka";
                name = "Eweka News Server";
                host = "news.eweka.nl";
              };
            };
          };

          prowlarr.enable = true;
          radarr.enable = true;
          sonarr.enable = true;
          lidarr.enable = true;

          bazarr.enable = true;

          jellyseerr = {
            enable = true;
            port = 4055;
            expose = true;
          };

          vpn = let
            name = "arr";
            privateKeyFile = config.sops.secrets."keys/proton/private-key".path;
            postUp = pkgs.writeShellApplication {
              name = "${name}-postup";
              runtimeInputs = with pkgs; [
                wireguard-tools
                iproute2
              ];
              text = ''
                ip netns exec ${name} wg set ${name}0 private-key <(cat ${privateKeyFile})
              '';
            };
            configDir = pkgs.writeTextFile {
              name = "config-${name}";
              executable = false;
              destination = "/${name}.conf";
              text = ''
                [Interface]
                Address = 10.2.0.2/32
                DNS = 10.2.0.1

                [Peer]
                PublicKey = D8Sqlj3TYwwnTkycV08HAlxcXXS3Ura4oamz8rB5ImM=
                AllowedIPs = 0.0.0.0/0, ::/0
                Endpoint = 103.69.224.4:51820
              '';
            };
            configFile = configDir + "/${name}.conf";
          in {
            enable = true;
            inherit name configFile;
            accessibleFrom = ["192.168.2.0/24"];
            postUp = postUp + "/bin/${name}-postup";
          };
        };

        traccar = {
          enable = true;
          protocols = ["osmand"];
          openFirewall = true;
          expose = true;
        };
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
