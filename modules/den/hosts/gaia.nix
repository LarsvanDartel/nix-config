# gaia (x86_64 server). den-produced.
#
# Generate the facter report on gaia and commit:
#   sudo nixos-facter -o modules/den/hosts/_facter/gaia.facter.json
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.gaia.users.nixos = {};

  den.aspects.gaia = {
    # Via provides.to-users: the user `nixos` collides with the aspect's
    # `nixos` key. On gaia because pioneer has no room for the 100 MiB index.
    provides.to-users.includes = [den.aspects.home.comma];

    includes = with den.aspects; [
      roles.server
      core.boot
      core.impermanence
      services.netbird
      services.crowdsec
      services.ntfy
      services.unbound
      services.gatus
      services.alloy
      services.restic
      # A broken netbird-proxy takes comin's update path with it; recovery
      # is deploy-rs over :2222, which is why that stays.
      services.comin
    ];

    nixos = {config, ...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {
          facter.reportPath = ./_facter/gaia.facter.json;
          # Headless: skip graphics (~800MB). Set here, not read from config,
          # to avoid recursion under den.
          facter.detected.graphics.enable = false;
        }
        inputs.disko.nixosModules.disko
        ./_hw/gaia/disko.nix
        ({lib, ...}: {
          # Public :22 is DNAT'd to the knot; admin on :2222. Inside
          # `imports`: a top-level mkForce recurses with facter (see pioneer.nix).
          services.openssh.ports = lib.mkForce [2222];
        })
      ];

      cosmos.system = {
        boot = {
          legacy = true;
          grub-device = "/dev/sda";
        };
        impermanence.device = "/dev/disk/by-label/nixos";
      };

      # Home IP, so a crowdsec ban can't lock the admin out of both paths.
      # Dynamic; keep until home.lvdar.nl (services/ddns.nix) resolves.
      cosmos.services.crowdsec.whitelistIps = ["86.86.217.11"];

      # No LAN behind this host. endeavour keeps :53 global for its LAN.
      cosmos.services.unbound.firewallInterfaces = [
        config.services.netbird.clients.default.interface
      ];

      # Same oisd list as endeavour: a public fallback would leak queries
      # and drop ad-blocking when something is already wrong.
      cosmos.services.unbound = {
        oisd = {
          enable = true;
          nsfw = true;
        };
        mesh.enable = true;
      };

      # NetBird's client owns mesh :53; same split as endeavour.
      cosmos.services.netbird.client.dnsResolverAddress = "127.0.0.1:15353";

      # netbird-mgmt's store.db *is* the mesh: losing it means re-enrolling
      # every peer. Excluded: crowdsec state/ (re-derived) and lookup tables.
      cosmos.services.restic = {
        repository = "sftp:u649268@u649268.your-storagebox.de:/gaia";

        paths = [
          "/persist/var/lib/netbird-mgmt"
          "/persist/var/lib/netbird"
          "/persist/var/lib/netbird-proxy"
          "/persist/var/lib/crowdsec"
          "/persist/var/lib/acme"
          "/persist/var/lib/unbound"
          # uid/gid map, so restored files keep their owners.
          "/persist/var/lib/nixos"
          # SSH host keys: sops-nix decrypts with them.
          "/persist/etc"
        ];

        exclude = [
          "/persist/var/lib/crowdsec/state"
          "/persist/var/lib/netbird-proxy/geolocation"
          "**/*.mmdb"
          "**/geonames_*.db"
        ];

        # Live SQLite store — see quiesceServices in services/restic.nix.
        quiesceServices = ["netbird-management.service"];
      };

      # Kernel NAT, not an L4 service: the L4 service for this target never
      # forwarded (cause unknown; traccar-osmand works). :2222 because
      # NetBird's agent takes mesh :22. Masquerade is required, or replies
      # go to the client's public address and never route back.
      networking.nat = {
        enable = true;
        externalInterface = "enp1s0";
        forwardPorts = [
          {
            sourcePort = 22;
            destination = "100.68.151.172:2222";
            proto = "tcp";
          }
        ];
        extraCommands = ''
          iptables -t nat -A POSTROUTING -d 100.68.151.172 -p tcp --dport 2222 -j MASQUERADE
          iptables -A FORWARD -d 100.68.151.172 -p tcp --dport 2222 -j ACCEPT
        '';
        extraStopCommands = ''
          iptables -t nat -D POSTROUTING -d 100.68.151.172 -p tcp --dport 2222 -j MASQUERADE || true
          iptables -D FORWARD -d 100.68.151.172 -p tcp --dport 2222 -j ACCEPT || true
        '';
      };

      # DNAT skips INPUT, but the port must still be open.
      networking.firewall.allowedTCPPorts = [22];

      cosmos.system.journald.maxUse = "512M";

      # Via nginx, not netbird-proxy: management needs kanidm to start and
      # the proxy needs management. Mesh literal: den can't read endeavour's
      # config; stable unless endeavour re-enrolls.
      cosmos.services.netbird.oidc.idp = {
        domain = "auth.lvdar.nl";
        upstream = "https://100.68.151.172:8443";
      };

      # netbird-proxy can't serve the apex (see www below). Ungated: a
      # public blog.
      cosmos.services.netbird.localVhosts."lvdar.nl".upstream = "http://100.68.151.172:3031";

      # Mesh-only (not in public DNS). Must match the other resolver's copy.
      cosmos.services.unbound.localRecords."idrac.lvdar.nl" = "100.68.78.148";

      # comin pulls, so no credential here grants anything on the fleet.
      cosmos.services.comin.repository = "https://knot.lvdar.nl/did:plc:a3erncqfgkcxu3yl6fpjfmwf";

      # Dotted names probe as written, bare labels as subdomains.
      cosmos.services.gatus.endpoints = [
        "lvdar.nl"
        "jellyfin"
        "immich"
        "traccar"
        "seerr"
        "cloud"
        "grafana"
        "ntfy"
        "auth"
        "kavita"
        "paperless"
        "bin"
      ];

      # Ad-blocking DNS follows roaming devices; gaia is the fallback.
      cosmos.services.netbird.dnsPeers = ["endeavour" "gaia"];

      # Non-fleet peers get DNS only. panther deliberately absent: it only
      # uses published names. `enforce` retires All -> All; getting it wrong
      # takes out SSH to everything at once.
      cosmos.services.netbird.mesh = {
        fleet = [
          "endeavour"
          "gaia"
          "pioneer"
          "voyager"
        ];
        resolvers = [
          "endeavour"
          "gaia"
        ];
        enforce = true;
      };

      # panther is a phone with no shell.
      cosmos.services.netbird.sshPeers = [
        "endeavour"
        "gaia"
        "pioneer"
        "voyager"
      ];

      # The only internet-reachable surface. Peer/port literals must track
      # the owning aspects (den can't read another host's config).
      cosmos.services.netbird.services = let
        endeavour = port: [
          {
            inherit port;
            peer = "endeavour";
          }
        ];

        shared = port: {
          bearerAuth.enable = false;
          targets = endeavour port;
        };
      in {
        # Own OIDC; docs/wopi can't be gated (editor iframe and Collabora
        # server-to-server fetch).
        cloud = shared 9200;
        docs = shared 9980;
        wopi = shared 9300;

        # Authenticates via oauth2-proxy + kanidm (firefly.nix).
        firefly = shared 8097;

        # Ungated: gating would put kanidm (on endeavour) in front of the
        # page that reports endeavour down.
        status = {
          bearerAuth.enable = false;
          targets = [
            {
              port = 8085;
              peer = "gaia";
            }
          ];
        };

        # Ungated: TaskChampion clients can't follow a redirect. The client
        # id (sops) is the allow-list; replicas encrypt client-side.
        task = shared 10222;

        # Ungated: the app uses username/password, and the outage notifier
        # must not depend on kanidm.
        ntfy = {
          bearerAuth.enable = false;
          targets = [
            {
              port = 8095;
              peer = "gaia";
            }
          ];
        };

        # Ungated: own OIDC, and its XHR can't follow the gate's 302
        # (the NetworkError that took traccar down).
        grafana = {
          bearerAuth.enable = false;
          targets = endeavour 3000;
        };

        typstnique = {
          bearerAuth.enable = false;
          targets = endeavour 3030;
        };

        # Own OIDC.
        tino = {
          bearerAuth.enable = false;
          targets = endeavour 3040;
        };

        # The apex can't be a proxy service (management 422s non-subdomains,
        # masked by the reconciler as "already taken"); served via
        # netbird.localVhosts. The app 301s www to the apex.
        www = {
          bearerAuth.enable = false;
          targets = endeavour 3031;
        };

        # SSE streams can't follow a lapsed gate's 302; own OIDC.
        chat = shared 8084;

        jellyfin = shared 8096;
        immich = shared 2283;
        seerr = shared 4055;

        # Creating a pasta needs MICROBIN_UPLOADER_PASSWORD.
        bin = shared 8087;

        # Own OIDC.
        paperless = shared 28981;

        # Own OIDC.
        kavita = shared 5000;

        # Git clients can't do an IdP redirect; writes are authenticated by
        # the knot against ATProto identity.
        knot = shared 5555;

        # The appview calls it service-to-service; can't follow a redirect.
        spindle = shared 6555;

        # XRPC clients carry their own tokens.
        pds = shared 3001;

        # XHR and the Manager app can't follow a gate redirect.
        traccar = shared 8082;

        # Must agree with cosmos.services.traccar.protocols on endeavour.
        traccar-osmand = {
          domain = "traccar-osmand.lvdar.nl";
          mode = "tcp";
          listenPort = 5055;
          bearerAuth.enable = false;
          targets = endeavour 5055;
        };

        # GATED: hands out a console. Gate is wider than the default because
        # the service authorises per server from the stamped groups. Groups
        # hand-synced with `inAppGroups` in services/kanidm.nix.
        minecraft-control = {
          domain = "minecraft.lvdar.nl";
          targets = endeavour 8086;
          bearerAuth.groups = [
            "netbird-minecraft-control"
            "netbird-minecraft-smp"
            "netbird-minecraft-hardcore"
          ];
        };

        # A game client can't follow an IdP redirect; endeavour's whitelist
        # is the access control. If it connects but never handshakes, try
        # target protocol = "tcp", or a DNAT like the knot's :22.
        minecraft-smp = {
          domain = "smp.lvdar.nl";
          mode = "tcp";
          listenPort = 25565;
          bearerAuth.enable = false;
          targets = endeavour 25565;
        };

        # L4 routes by listen port only, so a second port. The SRV record is
        # manual (the wildcard doesn't answer SRV):
        #   _minecraft._tcp.hardcore.lvdar.nl  SRV  0 0 25566 hardcore.lvdar.nl
        # Not Velocity: needs online-mode off + a forwarding secret.
        minecraft-hardcore = {
          domain = "hardcore.lvdar.nl";
          mode = "tcp";
          listenPort = 25566;
          bearerAuth.enable = false;
          targets = endeavour 25566;
        };

        # Simple Voice Chat. A broken voice port is silent ("voice chat
        # unavailable") while the game still works.
        minecraft-hardcore-voice = {
          domain = "hardcore-voice.lvdar.nl";
          mode = "udp";
          listenPort = 24454;
          bearerAuth.enable = false;
          targets = endeavour 24454;
        };

        suwayomi.targets = endeavour 8080;
        sabnzbd.targets = endeavour 6336;

        # API keys only, no login: the identity check is the only gate.
        prowlarr.targets = endeavour 9696;
        radarr.targets = endeavour 7878;
        sonarr.targets = endeavour 8989;
        lidarr.targets = endeavour 8686;
        bazarr.targets = endeavour 6767;
        lingarr.targets = endeavour 9876;
      };

      system.stateVersion = "24.11";
    };
  };
}
