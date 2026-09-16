# gaia (x86_64 server). den-produced.
#
# Hardware from a nixos-facter report; filesystems from disko. facter (unlike
# nixos-generate-config) doesn't force nixpkgs.hostPlatform in a way that
# recurses under den. Generate on gaia and commit:
#   sudo nixos-facter -o modules/den/hosts/_facter/gaia.facter.json
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.gaia.users.nixos = {};

  den.aspects.gaia = {
    # `, <cmd>` for the `nixos` user. Via provides.to-users, not the per-user
    # block voyager uses: this host's only user is named `nixos`, which
    # collides with the aspect's own `nixos` key. Routed through the host
    # because the prebuilt index is 100 MiB and pioneer has no room — see the
    # aspect.
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
      # GitOps: safe to automate — remote, most tedious by hand, smallest
      # closure. Pulls the knot through its own netbird-proxy, so a broken
      # proxy takes this host's update path with it; recovery is deploy-rs
      # over :2222, which is why that stays.
      services.comin
    ];

    nixos = {config, ...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {
          facter.reportPath = ./_facter/gaia.facter.json;
          # Headless VM: skip graphics detection (mesa/llvm ~800MB). Set alongside
          # reportPath so it isn't a config-read that recurses under den.
          facter.detected.graphics.enable = false;
        }
        inputs.disko.nixosModules.disko
        ./_hw/gaia/disko.nix
        ({lib, ...}: {
          # Public :22 belongs to the knot on endeavour now (DNAT below);
          # administration stays on :2222, which core/ssh.nix provides on
          # every host and deploy-rs has always used. Inside `imports`, not
          # the aspect body: a top-level mkForce recurses with facter (den
          # unwraps priority wrappers too early) — same trap as pioneer.nix.
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

      # The home connection, whitelisted so a bad afternoon here can't lock
      # the only administrator out of the only way in (a crowdsec ban
      # black-holes the WireGuard handshake, and the mesh path to fix it goes
      # with it). Dynamic, so it drifts; the durable replacement is
      # services/ddns.nix on endeavour (home.lvdar.nl, whitelisted by name).
      # This literal stays until that record resolves — an unresolvable
      # whitelistFqdns entry protects nothing.
      cosmos.services.crowdsec.whitelistIps = ["86.86.217.11"];

      # Mesh interface only: no LAN behind this host, so every legitimate
      # client arrives over wt0 and :53 need not answer on the internet at
      # all. endeavour deliberately keeps the global opening — its :53
      # serves home LAN clients as well as the mesh.
      cosmos.services.unbound.firewallInterfaces = [
        config.services.netbird.clients.default.interface
      ];

      # Backup mesh resolver with the same oisd list (~330 MB of 2.9 GB free)
      # — a public fallback would leak queries and silently drop ad-blocking
      # exactly when something is already wrong.
      cosmos.services.unbound = {
        oisd = {
          enable = true;
          nsfw = true;
        };
        mesh.enable = true;
      };

      # NetBird's client owns mesh :53 here, so unbound couldn't bind. Same
      # pattern as endeavour: fixed high port for the agent, 53 for unbound.
      cosmos.services.netbird.client.dnsResolverAddress = "127.0.0.1:15353";

      # The offsite copy of the edge. Small (~146 MB vs endeavour's 42 GB),
      # but netbird-mgmt's store.db *is* the mesh: losing it means
      # re-enrolling every peer on every device while the mesh is down.
      # Deliberately out: pangolin (decommissioned, dead state), crowdsec's
      # state/ (re-derived within hours; the 4 KB registration credentials
      # stay in), and the *.mmdb/geonames lookup tables.
      cosmos.services.restic = {
        repository = "sftp:u649268@u649268.your-storagebox.de:/gaia";

        paths = [
          "/persist/var/lib/netbird-mgmt"
          "/persist/var/lib/netbird"
          "/persist/var/lib/netbird-proxy"
          "/persist/var/lib/crowdsec"
          "/persist/var/lib/acme"
          "/persist/var/lib/unbound"
          # The uid/gid map: without it a rebuilt host hands out different
          # numeric owners than the restored files expect.
          "/persist/var/lib/nixos"
          # SSH host keys, which sops-nix decrypts with — without them a
          # restored host can't read any of its own secrets.
          "/persist/etc"
        ];

        exclude = [
          "/persist/var/lib/crowdsec/state"
          "/persist/var/lib/netbird-proxy/geolocation"
          "**/*.mmdb"
          "**/geonames_*.db"
        ];

        # netbird management keeps a live SQLite store — see quiesceServices
        # in services/restic.nix for why a running one is not copied.
        quiesceServices = ["netbird-management.service"];
      };

      # git over SSH for the knot: public :22 DNAT'd to endeavour's :2222
      # over the mesh. Kernel NAT, not an L4 service: the L4 service for this
      # target never forwarded (netbird-proxy bound :22, endeavour's sshd saw
      # nothing; a second L4 on an unprivileged port behaved the same). Not a
      # general L4 failure — traccar-osmand works — but why one peer reached
      # :5055 and not :2222 was never established. :2222 on the far side
      # because NetBird's agent redirects mesh :22 to its own SSH server. The
      # masquerade is not optional: without it endeavour replies to the
      # client's public address, which never routes back.
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

      # DNAT happens in PREROUTING and never reaches INPUT — but the port
      # must still be open for the packet to get that far.
      networking.firewall.allowedTCPPorts = [22];

      # 38G disk; the default 10% rule had grown the journal to 3.7G — too
      # much on the smallest host in the fleet.
      cosmos.system.journald.maxUse = "512M";

      # kanidm served by nginx here, not netbird-proxy: management cannot
      # start without it and the proxy cannot route without management. The
      # mesh address is a literal like the ports below — den can't read
      # another host's config; NetBird keeps it unless endeavour re-enrolls.
      cosmos.services.netbird.oidc.idp = {
        domain = "auth.lvdar.nl";
        upstream = "https://100.68.151.172:8443";
      };

      # The apex, which netbird-proxy cannot serve (the cluster domain is
      # lvdar.nl — see www below). Same nginx bypass, same literal mesh
      # address for endeavour. No CrowdSec, no NetBird gate: a public blog's
      # front page must be readable without an account on this fleet.
      cosmos.services.netbird.localVhosts."lvdar.nl".upstream = "http://100.68.151.172:3031";

      # Deliberately absent from public DNS: the wildcard sends every
      # lvdar.nl name to the edge, so off the mesh it finds nothing — the BMC
      # is reachable from the mesh only (services/idrac.nix on pioneer
      # explains why). Literal peer address that must match the other
      # resolver's copy; both hosts answer it so it survives either being
      # down.
      cosmos.services.unbound.localRecords."idrac.lvdar.nl" = "100.68.78.148";

      # The knot, over public HTTPS. The arrow points inward: comin pulls, so
      # no credential here grants anything on the fleet.
      cosmos.services.comin.repository = "https://knot.lvdar.nl/did:plc:a3erncqfgkcxu3yl6fpjfmwf";

      # The published surface worth probing — a fact about this deployment,
      # so here rather than defaulted in services/gatus.nix. Dotted names
      # probe as written, bare labels as subdomains. lvdar.nl is the front
      # door and the only watcher of services.site (past netbird-proxy, so
      # past CrowdSec). `auth` earns its place: kanidm failing takes grafana,
      # opencloud and the NetBird gate with it — one alert, not three.
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
        # All three answer a bare GET without credentials, so the existing
        # [STATUS] < 400 covers them.
        "kavita"
        "paperless"
        "bin"
      ];

      # Every peer resolves through endeavour's oisd-carrying unbound, so
      # ad-blocking DNS follows roaming devices; addresses are looked up at
      # reconcile time. This host is the fallback with the same list, so
      # losing endeavour doesn't quietly turn the ads back on.
      cosmos.services.netbird.dnsPeers = ["endeavour" "gaia"];

      # Who may talk to whom: the four machines are peers of each other;
      # anything else enrolled (a phone, a device given a published page)
      # gets DNS and nothing more. panther is deliberately absent despite
      # being trusted — it uses only gaia's published names, the proxy's own
      # path (all 1667 requests in endeavour's access log came via
      # netbird-proxy); fleet membership would buy it nothing. `enforce` is
      # what retires the All -> All rule, on now that the replacement rules
      # have been seen in the nftables chain on more than one host — getting
      # it wrong takes out SSH to everything at once.
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

      # Peers reachable with `netbird ssh <peer>`; panther is a phone with
      # no shell to offer.
      cosmos.services.netbird.sshPeers = [
        "endeavour"
        "gaia"
        "pioneer"
        "voyager"
      ];

      # The published surface, and the only one: with Pangolin gone this list
      # is what the internet can reach. Peer name + port literals (den can't
      # read another host's config) that must track the owning aspects
      # (jellyfin.nix, traccar.nix, …). Everything is gated by a NetBird
      # identity check unless it says otherwise. `cloud` (opencloud) is NOT
      # here: it was published through Pangolin and is not deployed from this
      # repo, so there is no peer or port to point at until it is.
      cosmos.services.netbird.services = let
        endeavour = port: [
          {
            inherit port;
            peer = "endeavour";
          }
        ];

        # Open, not gated: each has its own login, shared with people who
        # have no account here. Immich's own mobile OAuth flow also breaks
        # behind a browser-redirect gate.
        shared = port: {
          bearerAuth.enable = false;
          targets = endeavour port;
        };
      in {
        # OpenCloud runs its own OIDC against kanidm — a second check would
        # be the same login twice. docs/wopi cannot be gated at all: the
        # browser's editor iframe and Collabora's server-to-server fetch.
        cloud = shared 9200;
        docs = shared 9980;
        wopi = shared 9300;

        # No OIDC of its own, but authenticates through kanidm via
        # oauth2-proxy + remote_user_guard (firefly.nix) — a real login, so
        # `shared`, not a second redundant check.
        firefly = shared 8097;

        # Ungated: gating would put kanidm (on endeavour) in front of the
        # page whose job is to report that endeavour is down — a status page
        # sharing a failure domain with what it watches is decoration. The
        # disclosure is tiny and already public: domains that resolve anyway,
        # plus up/down; the gated services stay gated.
        status = {
          bearerAuth.enable = false;
          targets = [
            {
              port = 8085;
              peer = "gaia";
            }
          ];
        };

        # Ungated because it cannot be gated: native clients (taskwarrior,
        # TaskStrider) speak the TaskChampion protocol and nothing else — a
        # browser redirect is a parse error. The client id (a sops secret,
        # services/taskchampion.nix) is the allow-list; the replicas encrypt
        # before sending, so an attacker here reads ciphertext.
        task = shared 10222;

        # Ungated deliberately: the ntfy app authenticates with
        # username/password, not an interactive login — and the one service
        # needed during an outage must not depend on kanidm, the host most
        # likely to be the outage.
        ntfy = {
          bearerAuth.enable = false;
          targets = [
            {
              port = 8095;
              peer = "gaia";
            }
          ];
        };

        # Ungated: grafana does its own kanidm OIDC, so a gate is a second
        # login — and its XHR calls can't follow the gate's 302 to the IdP
        # (the NetworkError that took traccar down).
        grafana = {
          bearerAuth.enable = false;
          targets = endeavour 3000;
        };

        # Public, and unauthenticated by design.
        typstnique = {
          bearerAuth.enable = false;
          targets = endeavour 3030;
        };

        # Ungated: TINO does its own kanidm OIDC login — a gate would be the
        # same login twice.
        tino = {
          bearerAuth.enable = false;
          targets = endeavour 3040;
        };

        # The apex cannot be a proxy service: management rejects anything
        # that is not a subdomain of the cluster domain lvdar.nl (422
        # "requires a subdomain label"), and the reconciler's generic "domain
        # or listen port already taken" error hid that — the proxy answered
        # `unknown domain` while a service that looked configured was never
        # created. Served by this host's nginx via netbird.localVhosts
        # instead. www is an ordinary subdomain; the app 301s it to the apex.
        www = {
          bearerAuth.enable = false;
          targets = endeavour 3031;
        };

        # LibreChat: an SPA whose chat responses stream over SSE, so a lapsed
        # gate session answers a long-lived stream with a 302 the frontend
        # cannot follow — the traccar NetworkError, mid-answer. Runs its own
        # kanidm OIDC, so a gate would also be a second login.
        chat = shared 8084;

        jellyfin = shared 8096;
        immich = shared 2283;
        seerr = shared 4055;

        # A paste exists to be handed to someone: reads open, creating a
        # pasta needs MICROBIN_UPLOADER_PASSWORD.
        bin = shared 8087;

        # Own kanidm OIDC — a gate would be the same login twice.
        paperless = shared 28981;

        # Own kanidm OIDC, same as cloud/chat — the same login twice.
        kavita = shared 5000;

        # The knot's HTTP half. Ungated: git clients send basic auth or
        # nothing and cannot do an IdP redirect. Public read is by intent;
        # writes are authenticated by the knot against ATProto identity.
        knot = shared 5555;

        # Ungated for the same reason as the knot: the appview must reach it
        # to register and dispatch work — a service-to-service caller can't
        # follow a gate redirect to kanidm.
        spindle = shared 6555;

        # XRPC clients carry their own tokens; a 302 to kanidm is a bare
        # network error to them.
        pds = shared 3001;

        # Ungated: the web UI talks to /api over XHR and the Traccar Manager
        # app has no browser — a lapsed gate session hands them a redirect
        # instead of a 401, which the browser reports as a bare NetworkError.
        # Traccar has its own accounts.
        traccar = shared 8082;

        # The port trackers actually report to. Traccar runs a decoder per
        # protocol across 5001-5263 and this publishes the one in use — must
        # agree with cosmos.services.traccar.protocols on endeavour. L4, not
        # HTTP: a tracker speaks its own protocol on a raw socket, nothing to
        # terminate TLS on. The domain routes nothing; the listen port does.
        traccar-osmand = {
          domain = "traccar-osmand.lvdar.nl";
          mode = "tcp";
          listenPort = 5055;
          bearerAuth.enable = false;
          targets = endeavour 5055;
        };

        # The control page — the one Minecraft entry that is GATED, because
        # it hands out a console on a systemd unit (the game servers are
        # whitelisted). The gate is deliberately wider than the default
        # netbird-<name>: the service does its own per-server authorisation
        # from the groups netbird-proxy stamps, so gating on
        # netbird-minecraft-control alone would put the page behind the very
        # group that grants every server. Any of the three reaches the page;
        # minecraft.control.access on endeavour decides what you see. Groups
        # hand-synced with `inAppGroups` in services/kanidm.nix. HTTP, not
        # L4: TLS to terminate, a CrowdSec verdict worth applying, a human
        # can follow the IdP redirect.
        minecraft-control = {
          # The bare name: browsers want the page; players type
          # smp./hardcore., which took the prefixed names.
          domain = "minecraft.lvdar.nl";
          targets = endeavour 8086;
          bearerAuth.groups = [
            "netbird-minecraft-control"
            "netbird-minecraft-smp"
            "netbird-minecraft-hardcore"
          ];
        };

        # Minecraft, L4 for the same reason as traccar-osmand: the client
        # speaks Mojang's protocol on a socket — no TLS, no HTTP for
        # CrowdSec. bearerAuth off is not a preference: a game client cannot
        # follow an IdP redirect, so gating would publish a port no
        # Minecraft client can connect to; the whitelist on endeavour is the
        # access control. If it connects but never completes a handshake,
        # suspect the same unexplained L4 failure the knot's :22 hit — the
        # DNAT above is the proven way around it. The target inherits
        # protocol = "http" from the helper, which reads like a bug in an L4
        # service but is left alone: traccar-osmand renders identically and
        # works, so it is the known-good shape. Setting the target protocol
        # to "tcp" is the first thing to try if this does not forward.
        minecraft-smp = {
          domain = "smp.lvdar.nl";
          mode = "tcp";
          listenPort = 25565;
          bearerAuth.enable = false;
          targets = endeavour 25565;
        };

        # The second world: L4 routes by listen port and nothing else — a
        # TCP connection carries no hostname and every name under lvdar.nl
        # wildcards onto this address, so two services on 25565 would be one
        # socket. The SRV record hides the port (the Java client honours it);
        # it is manual — the wildcard answers A lookups but not SRV, and
        # without it hardcore.lvdar.nl:25566 still works:
        #   _minecraft._tcp.hardcore.lvdar.nl  SRV  0 0 25566 hardcore.lvdar.nl
        # A Velocity proxy could share 25565 by routing on the handshake
        # hostname, but it makes one process a dependency of both servers and
        # needs online-mode off plus a forwarding secret — whose failure mode
        # is anyone joining as anyone. Not worth it.
        minecraft-hardcore = {
          domain = "hardcore.lvdar.nl";
          mode = "tcp";
          listenPort = 25566;
          bearerAuth.enable = false;
          targets = endeavour 25566;
        };

        # Simple Voice Chat's audio, hardcore only: UDP on a second socket
        # beside the game's TCP 25566. 24454 is the mod default and the
        # client discovers the port from the server, so it matters only to
        # firewall readers; nothing collides. If voice breaks while the game
        # still works, check this — an unreachable voice port is silent by
        # design ("voice chat unavailable"), not a failure.
        minecraft-hardcore-voice = {
          domain = "hardcore-voice.lvdar.nl";
          mode = "udp";
          listenPort = 24454;
          bearerAuth.enable = false;
          targets = endeavour 24454;
        };

        suwayomi.targets = endeavour 8080;
        sabnzbd.targets = endeavour 6336;

        # The *arr suite runs on the host, not in the VPN namespace (only
        # the download clients are confined), so it is reached directly.
        # Each ships an API key rather than a login — the identity check in
        # front is the only thing between them and the internet.
        prowlarr.targets = endeavour 9696;
        radarr.targets = endeavour 7878;
        sonarr.targets = endeavour 8989;
        lidarr.targets = endeavour 8686;
        bazarr.targets = endeavour 6767;
      };

      system.stateVersion = "24.11";
    };
  };
}
