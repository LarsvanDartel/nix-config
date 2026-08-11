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
      services.tile-traccar
      services.netbird.client
      services.suwayomi
      services.opencloud
      services.typstnique
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
      services.transcode
      services.prometheus
      services.grafana
      services.loki
      services.alloy
    ];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: {
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

      # UEFI, not legacy BIOS. The scaffold commit copied gaia's settings here,
      # but gaia is a QEMU VM that really does boot BIOS off /dev/sda — this
      # host does not. disko gives `main` a 512M EF00 ESP mounted at /boot and
      # no bios_grub partition, so a BIOS grub-install has nowhere to embed
      # core.img and refuses ("will not proceed with blocklists"). /dev/sda is
      # also the wrong disk: with nine drives attached that is a SAS member of
      # the tank pool, not the Samsung M.2 the system lives on.
      #
      # Defaults are what this host wants: legacy = false gives efiSupport and
      # canTouchEfiVariables, and grub-device = null becomes device = "nodev".

      networking.hostId = "b8433556";

      # TLS for every published service now terminates on gaia, at
      # netbird-proxy, which forwards to each app's own port over the mesh.
      # Drops the local `<name>.lvdar.nl` vhosts — nothing reaches this host
      # by name any more, only by peer and port.
      cosmos.networking.edgeTerminated = true;

      cosmos.services.netbird.client = {
        # A stable port for the agent's resolver, so unbound has something to
        # forward the mesh domain to. Without it the agent picks an ephemeral
        # port, unbound answers *.lvdar.nl from public DNS, and every mesh name
        # on this host resolves to the edge's public address.
        #
        # 15353 rather than the conventional 5053, which traccar already owns
        # here as part of its 5001-5263 decoder range.
        dnsResolverAddress = "127.0.0.1:15353";

        # Publishes 192.168.2.0/24 into the mesh, so a roaming voyager reaches
        # the whole home network and not just the peers. Turns on IP
        # forwarding, which is why it is opt-in per host.
        routingFeatures = "server";

        # What netbird-proxy targets. Must track the service declarations in
        # gaia.nix — a port missing here is a published service that times
        # out rather than one that fails loudly.
        exposedPorts = [
          8443 # kanidm      auth.lvdar.nl
          8096 # jellyfin    jellyfin.lvdar.nl
          2283 # immich      immich.lvdar.nl
          8082 # traccar     traccar.lvdar.nl
          5055 # traccar     osmand tracker protocol, published L4 on :5055
          8080 # suwayomi    suwayomi.lvdar.nl
          4055 # jellyseerr  seerr.lvdar.nl     (via the netns bridge)
          6336 # sabnzbd     sabnzbd.lvdar.nl   (via the netns bridge)

          # The *arr suite. These run on the host rather than inside the VPN
          # namespace — only the download clients are confined — so they are
          # reached directly rather than through a bridge.
          9696 # prowlarr    prowlarr.lvdar.nl
          7878 # radarr      radarr.lvdar.nl
          8989 # sonarr      sonarr.lvdar.nl
          8686 # lidarr      lidarr.lvdar.nl
          6767 # bazarr      bazarr.lvdar.nl

          # OpenCloud and the two legs Collabora needs.
          9200 # opencloud   cloud.lvdar.nl
          9300 # wopi host   wopi.lvdar.nl   (server-to-server, from Collabora)
          9980 # collabora   docs.lvdar.nl

          3030 # typstnique  typstnique.lvdar.nl
        ];
      };

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
        # Answer for the mesh, and resolve mesh names locally. This host's
        # unbound already carries the oisd blocklist, so making it the fleet
        # resolver gives every peer ad-blocking DNS as a side effect.
        unbound.mesh.enable = true;

        unbound.oisd = {
          enable = true;
          nsfw = true;
        };

        # On the array rather than the system disk: this is the one service
        # here whose data is expected to grow without limit. /tank is a ZFS
        # pool outside the persist layer, so it is left out of impermanence on
        # purpose — the pool is the durable thing.
        opencloud.dataDir = "/tank/opencloud";

        jellyfin.openFirewall = true;
        immich.mediaDir = "/tank/media/library/images";

        # Moved here from voyager. The library and downloads do NOT come along
        # with the config — they live in /var/lib/suwayomi-{server,downloads}
        # on voyager and have to be copied across.
        suwayomi = {
          basicAuth.enable = true;
          webview.enable = true;
          # Same paths it used on voyager. Putting downloads under /tank would
          # be the obvious move on the host with the array, but the aspect adds
          # downloadsDir to impermanence — and /tank is a ZFS pool outside the
          # persist layer, so it would get a bind mount from /persist over the
          # top and land on the root disk anyway. Would need the aspect to stop
          # persisting an explicitly-placed downloadsDir first.
          downloadsDir = "/var/lib/suwayomi-downloads";
          homeLink = "/home/${config.cosmos.user.name}/manga";
        };

        # Sized to the nightly window rather than to the backlog. The first
        # file took 24 min for 27 GiB, so eight is roughly 03:00 to 06:00 —
        # done before anyone watches anything, and the GPU is shared with
        # jellyfin's transcoder. Raising this does not make the job finish
        # sooner so much as make it run later into the morning.
        transcode = {
          dryRun = false;
          maxPerRun = 8;
        };

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

        # Each tag needs a Traccar device whose identifier is the tag's UUID —
        # the feeder logs the UUID it is reporting for, which is where to read
        # them off.
        tile-traccar = {
          email = "larsvandartel73@gmail.com";
          # The phone the tags are discovered by. It carries the Tile app
          # rather than being a tag, so its "position" is just wherever the
          # phone is — which Traccar already gets from the OsmAnd client.
          ignoredTiles = ["p!fb79d495c0cb30211d73a246a5cc3c13"];
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
