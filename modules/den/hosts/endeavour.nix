# endeavour (x86_64 media/services server, intel+nvidia, ZFS). den-produced.
#
# Generate the facter report on it:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/endeavour.facter.json
#
# Dell Precision R7910: Xeon + Tesla P100 (compute only), Intel Arc A310 for
# transcoding, the BMC's Matrox for the console.
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.endeavour.users.nixos = {};

  den.aspects.endeavour = {
    # Via the host, not roles.home-base: pioneer has no room for the
    # 100 MiB index.
    provides.to-users.includes = [den.aspects.home.comma];

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
      services.kavita
      services.microbin
      services.paperless
      services.immich
      services.firefly
      services.traccar
      services.tile-traccar
      services.netbird.client
      services.comin
      # Only here: it pushes to main.
      services.flake-bump
      services.build-gate
      services.suwayomi
      services.flaresolverr
      # Lets gaia's crowdsec whitelist name home.lvdar.nl instead of a
      # drifting literal.
      services.ddns
      services.opencloud
      services.typstnique
      services.tino
      services.gewisMinutesWatcher
      services.site
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
      services.arr.lingarr
      services.arr.jellyseerr
      services.transcode
      services.prometheus
      services.grafana
      services.loki
      services.alloy
      services.sanoid
      services.smartd
      services.zed
      services.attic
      services.restic
      services.tangled
      services.tangled.spindle
      services.pds
      services.minecraft
      services.minecraft.control
      services.ollama.librechat
      services.taskchampion
    ];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      # By PCI slot, not renderD12x: probe order once (2026-08-28) handed
      # renderD128 to the Tesla, silently breaking VAAPI. by-path fails loudly.
      arcRenderNode = "/dev/dri/by-path/pci-0000:07:00.0-render";
    in {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {
          facter.reportPath = ./_facter/endeavour.facter.json;
          # Pinned off: otherwise a monitor present at the next facter run
          # puts every GPU driver (~100 MB nvidia firmware) in the initrd.
          # hardware.graphics.enable is set explicitly below.
          facter.detected.graphics.enable = false;
        }
        inputs.nixos-hardware.nixosModules.common-cpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.disko.nixosModules.disko
        ./_hw/endeavour/disko.nix
      ];

      # Boot defaults (UEFI, device "nodev") are correct; don't copy gaia's
      # legacy settings: there's no bios_grub partition, and /dev/sda is a
      # tank SAS member, not the system M.2.

      # DID of @lvdar.nl on this host's own PDS.
      cosmos.services.tangled.owner = "did:plc:wj6rsizbzc7fruoopsxg2k2a";

      # Push what the nightly lock bump builds here, or CI rebuilds it.
      cosmos.services.attic.client.watchStore.enable = true;

      cosmos.services.tino.accentColour = "red";

      # See services/ollama.nix for the package override (stock ollama-cuda
      # silently runs on CPU). The 14B pair are ~9 G each: one resident at a time.
      cosmos.services.ollama = {
        models = [
          "qwen3:14b"
          "qwen2.5-coder:14b"
          "llama3.1:8b"

          # Inline completion: 14B (12.5 tok/s) is too slow; 3B (~2 G) fits
          # beside a resident 14B and shares the FIM template.
          "qwen2.5-coder:3b"
        ];

        # ollama has no auth: every mesh peer gets free GPU use. Accepted:
        # the mesh is all enrolled devices; gaia publishes nothing on 11434
        # and the port opens on the NetBird interface only.
        meshExposed = true;
      };

      # Holds 25565: gaia's L4 has only one 25565 to give (hardcore uses
      # 25566 + SRV). Whitelist UUIDs from world/players/data; the UUID is
      # the identity, the name a mutable label.
      cosmos.services.minecraft.servers.smp = {
        motd = "lvdar.nl";
        whitelist = {
          Svenie23 = "1fd240dc-faa7-4a34-a12b-5465dec604d1";
          DeProGamer2015 = "584d73d3-c9e5-4d75-9fba-9c35d41531e7";
          DutchRD = "7239bc30-af4e-482c-9434-7ce3005cb917";
          Netwerk2009 = "88392a55-9cbc-4311-9fe1-9945a16abf72";
        };
        operators = {};
      };

      # `netbird-minecraft-control` is the gate on gaia; the per-server
      # groups below (checked against X-NetBird-Groups) decide which servers
      # a user gets. Gate group alone shows an empty page.
      cosmos.services.minecraft.control = {
        enable = true;

        # netbird-proxy's embedded client peer, not gaia's agent. Literal:
        # den can't read another host's config.
        proxyAddress = "100.68.242.26";

        access = {
          smp = ["netbird-minecraft-smp" "netbird-minecraft-control"];
          hardcore = ["netbird-minecraft-hardcore" "netbird-minecraft-control"];
        };
      };

      # Upstream's duplicate-port assertion only checks servers with
      # openFirewall, which this aspect disables — a clash would fail to bind
      # and roll back the deploy. SRV record is manual (see gaia.nix).
      cosmos.services.minecraft.servers.hardcore = {
        port = 25566;
        motd = "lvdar.nl — hardcore";
        whitelist = {
          DutchRD = "7239bc30-af4e-482c-9434-7ce3005cb917";
          PittyPfert = "f2bfe527-e914-4d2b-b72b-3f1708452082";
          # Same UUID as on smp.
          Svenie23 = "1fd240dc-faa7-4a34-a12b-5465dec604d1";
        };
        operators = {};

        # Here, not the shared packwiz pack: this world only. UDP 24454 needs
        # its own firewall hole and gaia L4 service; unreachable = silent
        # "voice chat unavailable".
        extraMods = [pkgs.simple-voice-chat];

        serverProperties = {
          hardcore = true;

          # Redundant under hardcore; pinned in case hardcore is turned off.
          difficulty = "hard";

          # Vanilla defaults, pinned so changing them is deliberate.
          pvp = true;
          spawn-monsters = true;

          # Spawn protection is pointless with a whitelist of two.
          spawn-protection = 0;

          # Server-side render ceiling; ~2.5x load per player vs 10.
          # Affordable: 36 cores, two players, C2ME + VMP in the pack.
          # simulation-distance stays 10: raising it changes gameplay.
          view-distance = 16;
        };
      };

      networking.hostId = "b8433556";

      # The iDRAC NIC self-assigns 169.254 instantly and dhcpcd counted it as
      # "online"; loki/alertmanager then died needing a real address and hit
      # start-limit. Deny it and wait for a real IPv4 lease.
      networking.dhcpcd = {
        wait = "ipv4";
        denyInterfaces = [
          "idrac"
          # The *arr container's veth/bridge have static addressing.
          "veth-*"
          "arr-br"
        ];
      };

      # TLS terminates at gaia's netbird-proxy; no local vhosts.
      cosmos.networking.edgeTerminated = true;

      # Mesh-only (not in public DNS). Must match the other resolver's copy.
      cosmos.services.unbound.localRecords."idrac.lvdar.nl" = "100.68.78.148";

      cosmos.services = {
        attic.dataDir = "/tank/atticd";
        loki.dataDir = "/tank/monitoring/loki";
        ollama.modelsDir = "/tank/ollama/models";

        # Credentials are sops secrets — see docs/RESTORE.md.
        restic.repository = "sftp:u649268@u649268.your-storagebox.de:/endeavour";

        tangled = {
          stateDir = "/tank/git";
          spindle.stateDir = "/tank/spindle";
        };

        # watchPath hardcodes the knot's on-disk layout and a DID: first
        # thing to check when a push stops triggering a build.
        build-gate = {
          repository = "git@knot.lvdar.nl:lvdar.nl/nix-config";
          watchPath = "/tank/git/did:plc:a3erncqfgkcxu3yl6fpjfmwf/refs/heads/main";
        };
        flake-bump = {
          repository = "git@knot.lvdar.nl:lvdar.nl/nix-config";
          gitEmail = "flake-bump@lvdar.nl";
        };
      };

      # comin pulls, so no credential here grants anything on the fleet.
      cosmos.services.comin.repository = "https://knot.lvdar.nl/did:plc:a3erncqfgkcxu3yl6fpjfmwf";

      # TaskChampion's only authentication (the port is published). In
      # hosts/common so voyager shares it.
      cosmos.services.taskchampion.clientIdFile =
        config.sops.secrets."keys/taskwarrior/client-id".path;

      # The postgres dump dir is absent on purpose: restic appends it itself.
      cosmos.services.restic.paths = [
        "/persist/var/lib/kanidm"
        "/persist/var/lib/traccar"
        "/persist/var/lib/arr"
        "/persist/var/lib/grafana"
        # Holds the PLC rotation key that proves control of the DID.
        "/persist/var/lib/pds"
        "/persist/var/lib/opencloud"
        # LibreChat (MongoDB + uploads); models are re-downloadable.
        "/persist/var/lib/librechat"
        "/persist/var/db/mongodb"
        # typstnique's leaderboard.
        "/persist/var/lib/typstnique"
        # Convenience only: every replica holds the full list; encrypted.
        "/persist/var/lib/taskchampion-sync-server"
        "/persist/home"
        # The ssh host key decrypts sops, incl. keys/zfs/tank: without it
        # nothing else (including /tank) is restorable.
        "/persist/etc"
        # uid/gid map, so restored files keep their owners.
        "/persist/var/lib/nixos"
        # On btrfs root SSD, so sanoid doesn't cover it: only copy.
        "/persist/var/lib/radicale"
        # database.mv.db matters; the 1.4 GB around it is excluded.
        # suwayomi-downloads is re-fetched by the download-retry timer.
        "/persist/var/lib/suwayomi-server"
        "/tank/opencloud"
        "/tank/media/library/images"
        # sanoid snapshots live in the pool they protect; this survives the array.
        "/tank/git"
        # Same as the knot.
        "/tank/minecraft"
      ];

      # roles/server.nix's 20s reset the box mid-build on 2026-08-28 (SEL:
      # Watchdog2 Hard reset). Same as pioneer. max-jobs below fixes the hang.
      systemd.settings.Manager.RuntimeWatchdogSec = lib.mkForce "60s";

      # max-jobs=auto (72) x cores=0 livelocked the host on memory (no swap,
      # uncapped ARC, no OOM entry). 8 x 8 bounds it to 64 compilers.
      nix.settings = {
        max-jobs = 8;
        cores = 8;
      };

      cosmos.services.netbird.client = {
        # Fixed port so unbound can forward the mesh domain to the agent
        # (else mesh names resolve to the edge). Not 5053: traccar owns it.
        dnsResolverAddress = "127.0.0.1:15353";

        # Advertises 192.168.2.0/24 to roaming peers; enables IP forwarding.
        routingFeatures = "server";

        # Must track gaia.nix's services: a missing port times out silently.
        exposedPorts = [
          8443 # kanidm      auth.lvdar.nl
          8096 # jellyfin    jellyfin.lvdar.nl
          2283 # immich      immich.lvdar.nl
          8082 # traccar     traccar.lvdar.nl
          5055 # traccar     osmand tracker protocol, published L4 on :5055
          8080 # suwayomi    suwayomi.lvdar.nl
          5000 # kavita      kavita.lvdar.nl
          8087 # microbin    bin.lvdar.nl  (nginx + oauth2-proxy, NOT microbin's own 8081)
          28981 # paperless   paperless.lvdar.nl
          4055 # jellyseerr  seerr.lvdar.nl     (via the netns bridge)
          6336 # sabnzbd     sabnzbd.lvdar.nl   (via the netns bridge)

          # *arr suite runs on the host, not in the VPN namespace.
          9696 # prowlarr    prowlarr.lvdar.nl
          7878 # radarr      radarr.lvdar.nl
          8989 # sonarr      sonarr.lvdar.nl
          8686 # lidarr      lidarr.lvdar.nl
          6767 # bazarr      bazarr.lvdar.nl
          9876 # lingarr     lingarr.lvdar.nl

          9200 # opencloud   cloud.lvdar.nl
          9300 # wopi host   wopi.lvdar.nl   (server-to-server, from Collabora)
          9980 # collabora   docs.lvdar.nl

          3030 # typstnique  typstnique.lvdar.nl
          3031 # site        lvdar.nl + www.lvdar.nl
          3040 # tino        tino.lvdar.nl
          8084 # librechat  chat.lvdar.nl
          8086 # mc control  minecraft.lvdar.nl

          # Mesh-only, absent from gaia.nix: unauthenticated inference API.
          11434 # ollama     (no public service)

          # Mesh-only, absent from gaia.nix: the NetBird ACL guards it.
          10222 # taskchampion (no public service)
        ];

        # Simple Voice Chat (hardcore); separate L4 service on gaia.
        exposedUdpPorts = [24454];
      };

      # gaia's agent address. gaia DNATs+masquerades public :22 here, so all
      # SSH arrives from one address and OpenSSH's srclimit penalised it,
      # resetting legitimate git traffic ("kex_exchange_identification:
      # Connection reset", build-gate 2026-08-15). crowdsec sheds scanners.
      services.openssh.settings.PerSourcePenaltyExemptList = "100.68.38.155";

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
          # i915, not xe: xe declines DG2 without force_probe, leaving the Arc
          # to a udev race it lost on 2026-08-28 (transcode broke). i915 here
          # loads in stage 1 and claims the card.
          driver = "i915";
          vaapiDriver = "intel-media-driver";
          enableHybridCodec = true;
        };
        graphics.enable = true;
      };

      boot = {
        kernelParams = ["nohibernate"];

        # Cap ARC at 16 GiB: fast builds outran ARC eviction and the watchdog
        # reset the host on 2026-08-28.
        extraModprobeConfig = ''
          options zfs zfs_arc_max=17179869184
        '';
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

        "keys/taskwarrior/client-id".sopsFile = "${builtins.toString inputs.nix-secrets}/hosts/common/secrets.yaml";
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
        # The fleet resolver: gives every peer oisd ad-blocking.
        unbound.mesh.enable = true;

        unbound.oisd = {
          enable = true;
          nsfw = true;
        };

        # /tank is outside the persist layer on purpose: the pool is durable.
        opencloud.dataDir = "/tank/opencloud";

        jellyfin = {
          openFirewall = true;
          vaapiDevice = arcRenderNode;
        };

        paperless.ai = {
          enable = true;
          model = "qwen3:14b";
        };
        immich = {
          mediaDir = "/tank/media/library/images";
          accelerationDevices = [arcRenderNode];
        };

        ddns.enable = true;

        # Library/downloads were not migrated from voyager with the config.
        suwayomi = {
          basicAuth.enable = true;
          # Not cosmos.user.name: "nixos" is the deploy account here.
          basicAuth.username = "lvdar";
          # Off since 2.3: libcef SIGTRAPs inside the FHS wrapper (exit 133)
          # and takes the whole server down. Not a missing lib nor the host;
          # likely chromium's sandbox nested in bubblewrap, with no knob for
          # --no-sandbox.
          webview.enable = false;

          # Loopback: flaresolverr is unauthenticated.
          flareSolverrUrl = "http://127.0.0.1:8191";
          # Not /tank: the aspect persists downloadsDir, so a /persist bind
          # mount would land it on the root disk anyway.
          downloadsDir = "/var/lib/suwayomi-downloads";
          homeLink = "/home/${config.cosmos.user.name}/manga";

          # Comick rate-limits past the downloader's three tries; see the
          # aspect for why it dequeues rather than restarts.
          downloadRetry.enable = true;
        };

        # Backlog grows (155 files / 140 GiB on 2026-08-30) faster than 8/night;
        # runs were CPU-bound, not encoder-bound, so 24 files, two at a time.
        transcode = {
          dryRun = false;
          maxPerRun = 24;
          parallel = 2;
          device = arcRenderNode;
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

        # Each tag needs a Traccar device whose identifier is the tag's UUID
        # (the feeder logs it).
        tile-traccar = {
          email = "larsvandartel73@gmail.com";
          # The phone carrying the Tile app; Traccar gets it via OsmAnd.
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
