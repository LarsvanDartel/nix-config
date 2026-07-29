# endeavour (x86_64 media/services server, intel+nvidia, ZFS). den-produced;
# named `endeavour` during the migration to avoid colliding with the old one.
#
# Hardware from a nixos-facter report; filesystems from disko. Generate on it:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/endeavour.facter.json
#
# Hardware: a Dell Precision R7910 — Xeon + Tesla P100 (compute only, no display),
# an Intel Arc A310 for transcoding, and the BMC's Matrox for the console.
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.endeavour.users.nixos = {};

  den.aspects.endeavour = {
    # host provides this home config to its users (just `nixos` here).
    provides.to-users.homeManager = {...}: {
      cosmos.system.impermanence.persist.directories = ["dev"];
    };

    includes = with den.aspects; [
      roles.server
      core.boot
      core.impermanence
      services.nginx
      services.unbound
      services.kanidm
      services.jellyfin
      services.immich
      services.traccar
      services.pangolin.newt
      services.cdrom
      hardware.ipmi-fancontrol
      services.arr.vpn
      services.arr.transmission
      services.arr.sabnzbd
      services.arr.prowlarr
      services.arr.radarr
      services.arr.sonarr
      services.arr.lidarr
      services.arr.bazarr
      services.arr.jellyseerr
    ];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.strings) splitString concatStringsSep;
      inherit (lib.lists) filter uniqueStrings;
    in {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {
          facter.reportPath = ./_facter/endeavour.facter.json;
          # facter turns its graphics module on when the report lists a monitor,
          # and then puts *every* detected GPU driver into the initrd. Here that
          # is nvidia (a Tesla P100, so ~100 MB of GSP firmware plus nvidia.ko),
          # i915 for the Arc card and mgag200 for the BMC console — none of which
          # is needed before stage 2. The report happens to have been taken with
          # nothing plugged in, so this is already off; pin it so plugging a
          # monitor in before the next `nixos-facter` run cannot silently change
          # the initrd. `hardware.graphics.enable` is set explicitly below, so
          # the userspace stack is unaffected.
          facter.detected.graphics.enable = false;
        }
        inputs.nixos-hardware.nixosModules.common-cpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.disko.nixosModules.disko
        ./_hw/endeavour/disko.nix
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

      sops.secrets = {
        "keys/zfs/tank" = {};
        "keys/proton/private-key" = {};
        "keys/eweka".owner = config.cosmos.services.arr.sabnzbd.user;
      };

      cosmos.system.impermanence = {
        device = "/dev/disk/by-label/nixos";
        persist.directories = [
          {
            directory = "/var/lib/arr";
            user = "root";
            group = "media";
            mode = "0770";
          }
        ];
      };

      cosmos.services = {
        unbound.blocklist = let
          lines = str: filter (x: x != "") (splitString "\n" str);
          bigLines = lines (builtins.readFile inputs.oisd-big-unbound);
          nsfwLines = lines (builtins.readFile inputs.oisd-nsfw-unbound);
          merged = concatStringsSep "\n" (uniqueStrings bigLines ++ nsfwLines);
          file = pkgs.writeText "unbound-blocklist" merged;
        in "${file}";

        jellyfin.openFirewall = true;
        immich.mediaDir = "/tank/media/library/images";

        arr = {
          stateDir = "/var/lib/arr";
          mediaDir = "/tank/media";

          transmission.vpn.enable = true;

          sabnzbd = {
            vpn.enable = true;
            secretFiles = [config.sops.secrets."keys/eweka".path];
            extraSettings = {
              misc.host_whitelist = "${config.networking.hostName}, sabnzbd.lvdar.nl";
              servers.eweka = {
                displayname = "Eweka";
                name = "Eweka News Server";
                host = "news.eweka.nl";
              };
            };
          };

          seerr.port = 4055;

          vpn = let
            name = "arr";
            privateKeyFile = config.sops.secrets."keys/proton/private-key".path;
            postUp = pkgs.writeShellApplication {
              name = "${name}-postup";
              runtimeInputs = with pkgs; [wireguard-tools iproute2];
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
            inherit name configFile;
            accessibleFrom = ["192.168.2.0/24"];
            postUp = postUp + "/bin/${name}-postup";
          };
        };

        traccar = {
          protocols = ["osmand"];
          openFirewall = false;
        };
      };

      cosmos.hardware.ipmi-fancontrol = {
        dynamic = true;
        minSpeed = 5;
        curve = 5.0;
        ignoreDevices = ["loc"];
        nvidia-smi = {
          enable = true;
          maxTemp = 105;
        };
      };

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
