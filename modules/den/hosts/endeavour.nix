# endeavour (x86_64 media/services server, intel+nvidia, ZFS). den-produced;
# named `endeavourd` during the migration to avoid colliding with the old one.
#
# Hardware from a nixos-facter report; filesystems from disko. Generate on it:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/endeavour.facter.json
#
# TODO (deferred until their aspects are converted): impermanence, nginx, unbound,
# kanidm, jellyfin, immich, traccar, pangolin-newt, cdrom, ipmi-fancontrol, the
# whole arr/VPN stack, and the service-coupled sops secrets (proton/eweka). This
# scaffold carries the baseline + server role + host hardware (nvidia/intel/zfs)
# so the facter report can be validated.
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.endeavourd = {
    hostName = "endeavour";
    users.nixos = {};
  };

  den.aspects.endeavourd = {
    includes = with den.aspects; [
      roles.server
      core.boot
    ];

    nixos = {
      config,
      lib,
      ...
    }: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/endeavour.facter.json;}
        inputs.nixos-hardware.nixosModules.common-cpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.disko.nixosModules.disko
        ../../hosts/endeavour/_hw/disko.nix
      ];

      cosmos.system.boot = {
        legacy = true;
        grub-device = "/dev/sda";
      };

      networking.hostId = "b8433556";

      hardware = {
        nvidia = {
          modesetting.enable = true;
          open = false;
          powerManagement.enable = true;
          nvidiaPersistenced = true;

          package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
            version = "580.126.18";
            sha256_64bit = "sha256-p3gbLhwtZcZYCRTHbnntRU0ClF34RxHAMwcKCSqatJ0=";
            sha256_aarch64 = lib.fakeSha256;
            openSha256 = lib.fakeSha256;
            settingsSha256 = "sha256-QMx4rUPEGp/8Mc+Bd8UmIet/Qr0GY8bnT/oDN8GAoEI=";
            persistencedSha256 = "sha256-ZBfPZyQKW9SkVdJ5cy0cxGap2oc7kyYRDOeM0XyfHfI=";
          };

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
        kernelParams = ["nohibernate"];
        supportedFilesystems = ["vfat" "zfs"];
        zfs = {
          extraPools = ["tank"];
          forceImportRoot = false;
        };
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

      system.stateVersion = "24.11";
    };
  };
}
