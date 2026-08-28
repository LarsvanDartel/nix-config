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
      services.comin
      # The scheduled lock bump. On this host because it has the build
      # capacity and the knot; nowhere else because it pushes to main.
      services.flake-bump
      services.build-gate
      services.suwayomi
      services.flaresolverr
      # Keeps home.lvdar.nl pointed at this connection, which is what lets
      # gaia's crowdsec whitelist name the home address instead of pinning a
      # literal that drifts. This is the host actually behind that connection.
      services.ddns
      services.opencloud
      services.typstnique
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
      services.ollama.webui
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

      # The DID of @lvdar.nl, the account on this host's own PDS. The knot is
      # owned by an identity we host rather than one Bluesky hosts, which is
      # the whole reason the PDS went in first.
      cosmos.services.tangled.owner = "did:plc:wj6rsizbzc7fruoopsxg2k2a";

      # This host both serves the cache and pushes to it. Not redundant: the
      # nightly lock bump builds all three x86_64 closures here, and without
      # this they would exist only in the local store — CI would still fetch
      # nothing and rebuild them inside the microVM the next morning.
      cosmos.services.attic.client.watchStore.enable = true;

      # The Tesla P100 finally has something to do. See services/ollama.nix for
      # why the package is overridden — a stock ollama-cuda would run on the
      # CPU here without saying so.
      #
      # Three models, ~23 G on /tank: a general one, a coding one, and a small
      # fast one. All comfortably inside 16 G of VRAM at Q4, with room left for
      # context — the 14B pair are ~9 G each, so only one is resident at a time
      # and swapping between them costs a reload.
      cosmos.services.ollama = {
        models = [
          "qwen3:14b"
          "qwen2.5-coder:14b"
          "llama3.1:8b"

          # For inline completion rather than chat, which is a different job
          # with a different constraint: ghost-text has to arrive inside the
          # pause between keystrokes, and the 14B above generates at 12.5 tok/s
          # — an order of magnitude too slow to ever feel like completion.
          #
          # 3B is the compromise. ~2 G, so it sits alongside a resident 14B in
          # the 16 G rather than evicting it, which matters because chat and
          # completion are wanted at the same time. Both tags carry the same
          # fill-in-middle template, so this understands <|fim_prefix|> and a
          # `suffix` parameter exactly as its larger sibling does.
          "qwen2.5-coder:3b"
        ];

        # Reachable from the rest of the mesh, not just from the web UI on
        # this host. Turned on knowingly: the option's own description spells
        # out that ollama has no authentication whatsoever, so this gives every
        # peer free use of the GPU and of whatever is loaded into it.
        #
        # Acceptable here because the mesh is not a public network — it is four
        # machines and a phone, all enrolled — and because the alternative is
        # that the card is only usable through a browser. Nothing on the
        # internet reaches this: gaia publishes no service pointing at 11434,
        # and the firewall opens the port on the NetBird interface alone.
        meshExposed = true;
      };

      # The survival server, published as `smp.lvdar.nl`. It holds the default
      # port, which is what keeps that address free of a port suffix: gaia
      # forwards its 25565 straight here, and L4 has only one 25565 to give.
      # The other world is on 25566 and buys the same bare address with an SRV
      # record instead — see the comment on `hardcore` below.
      #
      # `minecraft.lvdar.nl` is no longer this; it is the control page.
      #
      # The whitelist is enforced, so this list is exactly who can join and the
      # internet is everyone else. Taken from the restored world itself —
      # world/players/data/<uuid>.dat is the record of who has actually played
      # — and resolved to names through Mojang's session server, rather than
      # typed from memory. The UUID is the identity; the name is a label that
      # its owner can change without telling anyone, and Minecraft will follow
      # the UUID when they do.
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

      # Run the servers from a browser, for the people who play here and
      # administer nothing: start/stop, who is online, the console, the log.
      #
      # Two layers of kanidm groups. `netbird-minecraft-control` is the gate on
      # gaia and decides who sees the page at all; the per-server groups below
      # decide which servers they then get, and are checked against the
      # X-NetBird-Groups header. Being in the gate group alone now shows an
      # empty page — deliberately, so handing someone one server is the default
      # shape rather than an afterthought.
      #
      # netbird-minecraft-control stays on both because it is the group the
      # people who look after the whole thing are in.
      cosmos.services.minecraft.control = {
        enable = true;
        access = {
          smp = ["netbird-minecraft-smp" "netbird-minecraft-control"];
          hardcore = ["netbird-minecraft-hardcore" "netbird-minecraft-control"];
        };
      };

      # The second server, and the thing the comment above warned about: two
      # servers cannot both have the default port. Upstream's duplicate-port
      # assertion only inspects servers with openFirewall set, and this aspect
      # turns that off, so nothing would have caught it at eval — the first
      # server to start would take 25565 and the second would fail to bind,
      # trigger its OnFailure notification, and roll the deploy back.
      #
      # 25566 is published from gaia as its own L4 service, because L4 routes by
      # listen port and 25565 is already smp's. The port is invisible to players
      # anyway, via a Cloudflare SRV record the Java client resolves before it
      # connects:
      #
      #   _minecraft._tcp.hardcore.lvdar.nl  SRV  0 0 25566 hardcore.lvdar.nl
      #
      # so the address typed is a bare `hardcore.lvdar.nl`. That record is
      # manual — the *.lvdar.nl wildcard answers A lookups but not SRV — and if
      # it is missing this is still reachable as hardcore.lvdar.nl:25566.
      cosmos.services.minecraft.servers.hardcore = {
        port = 25566;
        motd = "lvdar.nl — hardcore";
        whitelist = {
          DutchRD = "7239bc30-af4e-482c-9434-7ce3005cb917";
          PittyPfert = "f2bfe527-e914-4d2b-b72b-3f1708452082";
          # Same UUID as on smp above — the account is the identity, the name
          # is a label its owner can change.
          Svenie23 = "1fd240dc-faa7-4a34-a12b-5465dec604d1";
        };
        operators = {};

        # Proximity voice chat, on this world only — hence extraMods rather
        # than the shared packwiz pack, which every server gets.
        #
        # It listens on UDP 24454 of its own, separate from the game's TCP
        # 25566, so it needs its own hole in the mesh firewall below and its own
        # L4 service on gaia. A server whose voice port is unreachable does not
        # fail: players connect, hear nothing, and see "voice chat unavailable",
        # which is a much quieter symptom than it deserves.
        #
        # The client mod is optional. Vanilla clients still join and play, they
        # just cannot talk; anyone who wants voice installs the same major
        # version from Modrinth.
        extraMods = [pkgs.simple-voice-chat];

        serverProperties = {
          # What actually makes it hardcore. The server locks difficulty to
          # hard and puts a player who dies into spectator mode rather than
          # respawning them — on a multiplayer world that is the whole game.
          hardcore = true;

          # Redundant while hardcore is true, which forces hard regardless, and
          # set anyway: it is the line that keeps meaning what it says if
          # hardcore is ever turned off, instead of silently dropping the world
          # back to normal difficulty.
          difficulty = "hard";

          # A death is permanent here, so the two settings that quietly undo
          # that are worth pinning rather than inheriting. Both are already the
          # vanilla defaults; the point is that a future edit has to be
          # deliberate.
          pvp = true;
          spawn-monsters = true;

          # Off. The default 16-block radius stops anyone who is not an
          # operator from building near spawn, which is a defence against
          # strangers griefing the spawn point on a public server — and this
          # server has an enforced whitelist of two, so it protects nobody and
          # only gets in the way of the first shelter.
          spawn-protection = 0;

          # How far the server *sends* chunks, and therefore the ceiling on
          # what any client can render however high it sets its own slider.
          # 10 is the vanilla default; chunks scale with the square of this, so
          # 16 is about 2.5x the load per player.
          #
          # Affordable here for reasons specific to this setup: 36 cores, 35
          # GiB free, two players — and the pack carries C2ME, which
          # parallelises chunk loading, and VMP, which optimises chunk sending.
          # Chunk sending is precisely the view-distance bottleneck, so this is
          # the one place those two mods pay for themselves.
          #
          # simulation-distance is deliberately left at 10. It governs where
          # entities tick, redstone runs and mobs spawn — raising it changes
          # gameplay and costs CPU every tick, which is a different decision
          # from "can I see further".
          view-distance = 16;
        };
      };

      networking.hostId = "b8433556";

      # network-online.target was firing about four seconds before this host
      # actually had a usable address, and services that need one to advertise
      # themselves died in that window:
      #
      #   25.621  idrac: leased 169.254.0.2      <- satisfies wait = "any"
      #   25.716  Reached target Network is Online
      #   25.761  loki          "no useable address found for interfaces"
      #   25.910  alertmanager  "no private IP found"
      #   29.895  eno1: leased 192.168.2.101     <- the address they needed
      #
      # Both then burned their restart budget in seconds and stayed in
      # start-limit-hit, so the host booted with no log ingestion and no alert
      # delivery — the second of which means the failure could not report
      # itself. Ordering them after network-online.target fixes nothing, since
      # they already are: the target was simply lying.
      #
      # The liar is the iDRAC's out-of-band management NIC, which self-assigns a
      # link-local 169.254 address almost immediately. dhcpcd counts that as
      # "an address" and declares the network up. It is a BMC that the host has
      # no business configuring, so it is denied outright, and the wait is
      # narrowed to a real IPv4 lease.
      #
      # Only surfaced now because this host had been up since 10 June; the
      # impermanence work is what made anyone reboot it.
      networking.dhcpcd = {
        wait = "ipv4";
        denyInterfaces = [
          "idrac"
          # dhcpcd was also soliciting leases on the *arr container's veth and
          # bridge, which have their own static addressing.
          "veth-*"
          "arr-br"
        ];
      };

      # TLS for every published service now terminates on gaia, at
      # netbird-proxy, which forwards to each app's own port over the mesh.
      # Drops the local `<name>.lvdar.nl` vhosts — nothing reaches this host
      # by name any more, only by peer and port.
      cosmos.networking.edgeTerminated = true;

      # roles/server.nix sets 20s, which is too tight for the host that builds
      # the fleet. On 2026-08-28 flake-bump's nixpkgs bump rebuilt obs-studio,
      # mcrl2 and the nvidia stack at once; every local service stalled for
      # seconds (loki timing out to its own ingester on 127.0.0.1, nats
      # readloops at 7.6s), PID 1 missed the 20s deadline, and iTCO_wdt reset
      # the box mid-build. The journal simply stops at 05:41:33; the SEL
      # recorded `Watchdog2 | Hard reset` at 05:42:29.
      #
      # 60s, matching hosts/pioneer.nix, which raised it for exactly the same
      # reason — a host that legitimately stalls under IO should not be reset
      # for surviving it slowly. This does not paper over the hang: max-jobs
      # below is what stops the machine getting there.
      systemd.settings.Manager.RuntimeWatchdogSec = lib.mkForce "60s";

      # 72 threads meant `max-jobs = auto` resolved to 72, and `cores = 0`
      # gives each of those every core — so nix was free to run 72 concurrent
      # derivations with no bound on total compiler processes. Memory is what
      # ran out first, and with no swap and an uncapped ARC there was no
      # reclaim path: the kernel livelocked instead of OOM-killing anything,
      # which is why the journal has no OOM entry.
      #
      # 8 x 8 bounds it to 64 concurrent compilers, close to the same CPU
      # utilisation with a fraction of the peak RSS. It slows a cold rebuild of
      # the whole fleet, which is a fair trade against a host that stops
      # answering: build-gate and flake-bump both already run at Nice 10 with
      # idle IO precisely because finishing quickly is not the point here.
      nix.settings = {
        max-jobs = 8;
        cores = 8;
      };

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
          3031 # site        lvdar.nl + www.lvdar.nl
          8084 # open-webui  chat.lvdar.nl
          8086 # mc control  minecraft.lvdar.nl

          # ollama's API, mesh-only and deliberately absent from gaia.nix —
          # unlike every other port in this list, publishing this one would
          # expose an unauthenticated API that runs arbitrary inference.
          11434 # ollama     (no public service)
        ];

        # Simple Voice Chat on the hardcore server. UDP because it carries
        # audio, and on its own port rather than multiplexed onto the game's
        # TCP 25566 — the two are unrelated sockets and gaia publishes them as
        # two separate L4 services.
        exposedUdpPorts = [24454];
      };

      # gaia's mesh address, exempted from OpenSSH's per-source penalties.
      #
      # gaia DNATs the public :22 to this host's :2222 and masquerades on the
      # way (see the `networking.nat` block in gaia.nix, which explains why the
      # masquerade is not optional). The consequence is that every SSH
      # connection from the entire internet arrives here from one address —
      # gaia's agent at 100.68.38.155 — and OpenSSH's srclimit, on by default
      # since 9.8, assumes a source address identifies a client. Behind a NAT
      # it does not.
      #
      # So an internet scanner failing auth against knot.lvdar.nl:22, which
      # happens continuously on a public VPS, accrues penalty against gaia and
      # sshd then resets *legitimate* git traffic over the same address: comin's
      # pulls, build-gate's fetch, and a plain `git push`. It presents as an
      # intermittent "kex_exchange_identification: Connection reset by peer"
      # that clears on its own, which is why it read as flakiness rather than
      # policy. build-gate failed exactly this way on 2026-08-15.
      #
      # Exempting the proxy loses little: that address is reachable only over
      # the mesh, auth here stays publickey-only, and crowdsec on gaia is what
      # actually sheds scanner traffic at the edge. The alternative — preserving
      # the client address with TPROXY or proxy-protocol — is a great deal more
      # machinery for the same result.
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
          driver = "xe";
          vaapiDriver = "intel-media-driver";
          enableHybridCodec = true;
        };
        graphics.enable = true;
      };

      boot = {
        kernelParams = ["nohibernate"];

        # Cap the ZFS ARC at 16 GiB of the 62 GiB installed.
        #
        # ARC defaults to half of RAM and is reclaimable only slowly and
        # asynchronously — a build that allocates fast can outrun ARC eviction,
        # and on 2026-08-28 that ended with the machine hung and the hardware
        # watchdog hard-resetting it (SEL entry 0x92). Handing 15 GiB back to
        # the page cache and to builds costs some read cache on a pool that is
        # mostly cold media anyway.
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

        ddns.enable = true;

        # Moved here from voyager. The library and downloads do NOT come along
        # with the config — they live in /var/lib/suwayomi-{server,downloads}
        # on voyager and have to be copied across.
        suwayomi = {
          basicAuth.enable = true;
          # Explicit rather than the aspect's default of cosmos.user.name,
          # which is "nixos" on this host and is the fleet's deploy account
          # rather than a person.
          basicAuth.username = "lvdar";
          # Off since the 2.3 bump. Inside the FHS wrapper libcef.so takes a
          # SIGTRAP and the server exits 133 before ever binding 8080, so the
          # whole service was down rather than just the bypass. Clearing the
          # 519 MB kcef cache changed nothing; it re-downloads and dies the same
          # way.
          #
          # What it is NOT, both checked rather than assumed: not a missing
          # library — every soname libcef.so wants is present inside the FHS
          # env — and not this host being hostile to browsers, since the same
          # chromium store path runs headless and sandboxed here as the
          # suwayomi user, exit 0. voyager only ever looked healthier because it
          # ran 2.1, whose CEF build worked; the variable is the version, not
          # the machine.
          #
          # The remaining suspect is chromium's sandbox failing to initialise
          # nested inside bubblewrap, which is what buildFHSEnv uses. Suwayomi
          # exposes no knob to pass CEF a --no-sandbox, so there is nothing to
          # try from here without patching it.
          #
          # The cost is Cloudflare-protected sources. FlareSolverr was tried as
          # a replacement and reverted: 3.5.0's undetected-chromedriver cannot
          # drive chromium 151 and crashlooped on startup, host-independently.
          webview.enable = false;

          # What covers Cloudflare instead. Loopback: flaresolverr is
          # unauthenticated and fetches whatever URL it is handed.
          flareSolverrUrl = "http://127.0.0.1:8191";
          # Same paths it used on voyager. Putting downloads under /tank would
          # be the obvious move on the host with the array, but the aspect adds
          # downloadsDir to impermanence — and /tank is a ZFS pool outside the
          # persist layer, so it would get a bind mount from /persist over the
          # top and land on the root disk anyway. Would need the aspect to stop
          # persisting an explicitly-placed downloadsDir first.
          downloadsDir = "/var/lib/suwayomi-downloads";
          homeLink = "/home/${config.cosmos.user.name}/manga";

          # Comick rate-limits hard enough that a chapter rarely survives the
          # downloader's three tries. See the aspect for why this needs a
          # dequeue rather than a restart.
          downloadRetry.enable = true;
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
