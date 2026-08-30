# gaia (x86_64 server). den-produced; named `gaia` during the migration to
# avoid colliding with the old `gaia`.
#
# Hardware comes from a nixos-facter report (generate on the host — see below);
# filesystems from disko. This is the clean den hardware path: facter (unlike a
# nixos-generate-config hardware-configuration.nix) does not force
# nixpkgs.hostPlatform in a way that recurses, since den owns the host system.
#
# Generate the report on gaia and commit it:
#   sudo nixos-facter -o modules/den/hosts/_facter/gaia.facter.json
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.gaia.users.nixos = {};

  den.aspects.gaia = {
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
      # GitOps. Safe to automate here: remote, the most tedious host to deploy
      # by hand, and the smallest closure in the fleet. Note it now pulls the
      # knot through its own netbird-proxy — so a change that breaks the proxy
      # takes this host's own update path with it, and the recovery is
      # deploy-rs over :2222, which still works and is why that stays.
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
          # Public :22 belongs to the tangled knot on endeavour now, forwarded
          # by the DNAT below. Administration moves to :2222, which core/ssh.nix
          # has provided on every host from the start and which deploy-rs has
          # used for every deploy — so this removes a second door rather than
          # the only one.
          #
          # Inside `imports` rather than the aspect body: a mkForce at the top
          # level recurses when combined with facter, because den unwraps
          # priority wrappers to classify content and forces the definition too
          # early. hosts/pioneer.nix documents the same trap.
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

      # The home connection, so a bad afternoon of poking at these services
      # cannot lock the only administrator out of the only way in. This is not
      # politeness: the bouncer drops in nftables, so a ban here black-holes the
      # WireGuard handshake as well as HTTP, and the mesh path to fix it goes
      # with it.
      #
      # Dynamic, so it will drift — and on the day it does this stops covering
      # this household and starts covering whoever inherits the address. The
      # previous comment here claimed the lvdar.nl entry in whitelistFqdns was
      # "the durable half"; it is not, lvdar.nl resolves to gaia rather than to
      # home, so nothing covered this.
      #
      # The replacement is services/ddns.nix on endeavour, which is the host
      # actually behind this connection: it keeps home.lvdar.nl pointed here and
      # crowdsec whitelists it by name. That needs a Cloudflare token endeavour
      # can use — keys/cloudflare/dns, which is now per host rather than one
      # shared credential, so endeavour's is scoped to the home connection and
      # gaia's to this address. Until the record resolves, this literal stays.
      # Swapping too early is worse than leaving it: an unresolvable name in
      # whitelistFqdns is evaluated per alert and protects nothing.
      cosmos.services.crowdsec.whitelistIps = ["86.86.217.11"];

      # Mesh interface only. This host has exactly two interfaces — wt0 and the
      # public enp1s0 — and no LAN behind it, so every legitimate client of this
      # resolver arrives over the mesh. Unscoped, :53 was a listener reachable
      # from the internet; access-control REFUSED those queries, so it was never
      # an open resolver, but there is no reason for the port to answer at all
      # out there. endeavour deliberately keeps the global opening: its :53 is
      # behind home NAT and serves LAN clients as well as the mesh.
      cosmos.services.unbound.firewallInterfaces = [
        config.services.netbird.clients.default.interface
      ];

      # The backup resolver for the mesh. unbound with the oisd list costs
      # ~330 MB here, against ~2.9 GB free — affordable, and the alternative
      # (a public resolver as fallback) would leak queries and silently drop
      # ad-blocking exactly when something is already wrong.
      cosmos.services.unbound = {
        oisd = {
          enable = true;
          nsfw = true;
        };
        mesh.enable = true;
      };

      # NetBird's client owns :53 on the mesh address here, so unbound could
      # not bind. Same pattern as endeavour: give the agent a fixed high port
      # and let unbound have 53.
      cosmos.services.netbird.client.dnsResolverAddress = "127.0.0.1:15353";

      # The offsite copy of the edge. Small — ~146 MB against endeavour's
      # 42 GB — but this is the host whose loss is hardest to undo by hand:
      # netbird-mgmt's store.db *is* the mesh. Rebuilding it means re-enrolling
      # every peer on every device, including the phones, and re-issuing the
      # setup keys, while the mesh those devices are enrolled in is down.
      #
      # Deliberately out:
      #   * pangolin (254 MB) — decommissioned, see the netbird.services comment
      #     below. Dead state on disk, not something to keep a year of copies of.
      #   * crowdsec's state/ — a 246 MB SQLite of bans plus 72 MB of GeoLite
      #     databases, all of it re-derived within hours of a fresh start and
      #     all of it churning nightly. What is worth keeping is the two 4 KB
      #     credential files that register this machine with the local and
      #     online APIs, which is what stays in.
      #   * netbird-proxy/geolocation and netbird-mgmt's own *.mmdb/geonames —
      #     138 MB of downloadable lookup tables.
      cosmos.services.restic = {
        repository = "sftp:u649268@u649268.your-storagebox.de:/gaia";

        paths = [
          "/persist/var/lib/netbird-mgmt"
          "/persist/var/lib/netbird"
          "/persist/var/lib/netbird-proxy"
          "/persist/var/lib/crowdsec"
          "/persist/var/lib/acme"
          "/persist/var/lib/unbound"
          # The uid/gid map. Small, and without it a rebuilt host hands out
          # different numeric owners than the files being restored expect.
          "/persist/var/lib/nixos"
          # SSH host keys, which are also what sops-nix decrypts with — restore
          # a host without them and it cannot read any of its own secrets.
          "/persist/etc"
        ];

        exclude = [
          "/persist/var/lib/crowdsec/state"
          "/persist/var/lib/netbird-proxy/geolocation"
          "**/*.mmdb"
          "**/geonames_*.db"
        ];

        # netbird management keeps a live SQLite store; see quiesceServices in
        # services/restic.nix for why a running one is not copied in place.
        quiesceServices = ["netbird-management.service"];
      };

      # git over SSH for the tangled knot: public :22 here to OpenSSH on
      # endeavour, over the mesh.
      #
      # Kernel NAT rather than a netbird.services entry, because the L4
      # (`mode = "tcp"`) service for this specific target never forwarded:
      # netbird-proxy bound :22, accepted connections, and endeavour's sshd
      # never saw them. A second L4 service on an unprivileged port behaved the
      # same, so it was not about privileged ports.
      #
      # Note this is *not* a general failure of L4 mode — traccar-osmand below
      # demonstrably works, and a packet capture shows its traffic arriving on
      # endeavour from 100.68.151.231, netbird-proxy's own embedded client peer
      # (distinct from gaia's agent at 100.68.38.155). Why that peer could
      # reach :5055 and not :2222 was never established. The DNAT sidesteps the
      # question entirely by not involving the proxy.
      #
      # :2222 and not :22 on the far side. NetBird's agent redirects
      # <mesh-ip>:22 to its own embedded SSH server — proven here, it answers
      # `SSH-2.0-NetBird-SSH-Server … JWT-Required` — so aiming at :22 would
      # hand every git push to the wrong daemon. core/ssh.nix explains why the
      # second port exists; this is what it is for.
      #
      # The masquerade is not optional. Without it endeavour would reply
      # straight to the client's public address, which never routes back, and
      # the connection would hang exactly like the proxy did.
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

      # DNAT happens in PREROUTING, so this never reaches the INPUT chain the
      # firewall guards — but the port still has to be open for the packet to
      # get that far.
      networking.firewall.allowedTCPPorts = [22];

      # 38G disk, and the journal had grown to 3.7G of it under the default
      # "10% of the filesystem" rule. A tenth of the disk is not a sensible
      # price for logs on the smallest host in the fleet.
      cosmos.system.journald.maxUse = "512M";

      # kanidm is served by nginx here rather than by netbird-proxy, because
      # management cannot start without it and the proxy cannot route without
      # management. The mesh address is a literal for the same reason the ports
      # below are: den cannot read another host's config. NetBird assigns it at
      # enrollment and keeps it, so it only changes if endeavour is re-enrolled.
      cosmos.services.netbird.oidc.idp = {
        domain = "auth.lvdar.nl";
        upstream = "https://100.68.151.172:8443";
      };

      # lvdar.nl itself, which netbird-proxy cannot serve (see the note in the
      # services list above). Same bypass as the IdP directly overhead, and the
      # same literal mesh address for endeavour, for the same reason: den cannot
      # read another host's config.
      #
      # This means the site gets no CrowdSec and no NetBird gate. Both are fine
      # here and neither would have been wanted: it is a public blog, and the
      # gate would have made the front page unreadable to everyone without an
      # account on this fleet.
      cosmos.services.netbird.localVhosts."lvdar.nl".upstream = "http://100.68.151.172:3031";

      # idrac.lvdar.nl is deliberately absent from public DNS: the wildcard
      # sends every lvdar.nl name to the edge, so off the mesh it resolves to
      # gaia and finds nothing. The BMC is reachable from the mesh and nowhere
      # else — services/idrac.nix on pioneer explains why.
      #
      # A literal peer address, like every other cross-host reference here.
      # This must match the other resolver's copy; both hosts answer it so the
      # name keeps resolving when either is down, which is the entire point of
      # publishing the BMC away from endeavour.
      cosmos.services.unbound.localRecords."idrac.lvdar.nl" = "100.68.78.148";

      # The knot, over public HTTPS. The arrow points inward: comin pulls, so
      # no credential here grants anything on the fleet.
      cosmos.services.comin.repository = "https://knot.lvdar.nl/did:plc:a3erncqfgkcxu3yl6fpjfmwf";

      # The published surface worth probing, listed here rather than defaulted
      # in services/gatus.nix: what matters to watch is a fact about this
      # deployment, not about a status page.
      #
      # A dotted name is probed as written, a bare label as a subdomain — which
      # is how the apex appears alongside the rest. lvdar.nl is the front door
      # and now the only thing watching services.site, which comes in past
      # netbird-proxy and so past CrowdSec.
      #
      # `auth` earns its place: kanidm failing takes grafana, opencloud and the
      # NetBird gate with it, and that is one alert rather than three confusing
      # ones.
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
        # All three answer a bare GET without credentials — 200 for kavita, a
        # redirect to kanidm for paperless and to oauth2-proxy for bin — so the
        # existing `[STATUS] < 400` covers them without special-casing.
        "kavita"
        "paperless"
        "bin"
      ];

      # Every peer resolves through endeavour's unbound, which carries the oisd
      # blocklist — so ad-blocking DNS follows a roaming laptop or phone around
      # instead of stopping at the front door. Addresses are looked up at
      # reconcile time, not written here.
      #
      # This host is the fallback, with the same blocklist, so losing endeavour
      # costs name resolution nothing and does not quietly turn the ads back
      # on. It is a reasonable second: if *it* is down the mesh is down anyway,
      # so it adds no failure mode that was not already fatal.
      cosmos.services.netbird.dnsPeers = ["endeavour" "gaia"];

      # Who may talk to whom on the mesh. The four machines are peers of each
      # other; anything else enrolled — a phone, or a device belonging to
      # somebody given a published web page — gets DNS and nothing more.
      #
      # panther is deliberately absent from the fleet despite being trusted. It
      # reaches every service it uses through gaia's published names, which is
      # the proxy's own path and unaffected by this: of 1667 requests in
      # endeavour's access log, all 1667 came from netbird-proxy and none
      # directly from a peer. Being in the fleet would buy it nothing and cost
      # the distinction this is drawing.
      #
      # `enforce` is what actually retires the All -> All rule. Left off until
      # the replacement rules have been seen in the nftables chain on more than
      # one host, because getting this wrong takes out SSH to everything at
      # once.
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

      # Peers reachable with `netbird ssh <peer>`. Names, not ids, resolved by
      # the reconciler like everything else here. panther is somebody's phone,
      # which has no shell to offer.
      cosmos.services.netbird.sshPeers = [
        "endeavour"
        "gaia"
        "pioneer"
        "voyager"
      ];

      # The published surface, and the only one: with Pangolin gone this list
      # is what the internet can reach. Targets are peer name + port, because
      # den has no way to read another host's config — so the ports are
      # literals here and must track the aspects that own them (jellyfin.nix,
      # traccar.nix, …).
      #
      # Everything is gated by a NetBird identity check unless it says
      # otherwise. `cloud.lvdar.nl` (opencloud) is NOT here and is therefore
      # dark: it was published through Pangolin but is not deployed from this
      # repo at all, so there is no peer or port to point at until it is.
      cosmos.services.netbird.services = let
        endeavour = port: [
          {
            inherit port;
            peer = "endeavour";
          }
        ];

        # Open, not gated. Each of these has its own login and is shared with
        # people who have no account here, and a NetBird check in front would
        # make them get one first. Immich also drives its own OAuth flow from
        # the mobile app, which a browser-redirect gate breaks outright.
        shared = port: {
          bearerAuth.enable = false;
          targets = endeavour port;
        };
      in {
        # OpenCloud runs its own OIDC against kanidm, so a second identity
        # check in front would ask for the same login twice. `docs` and `wopi`
        # cannot be gated at all: they are the browser's editor iframe and
        # Collabora's server-to-server fetch, neither of which can complete an
        # interactive login.
        cloud = shared 9200;
        docs = shared 9980;
        wopi = shared 9300;

        # The status page, ungated for the same reason as ntfy and then some.
        # Gating it would put kanidm in front — and kanidm runs on endeavour,
        # so a page whose entire job is to tell you endeavour is down would
        # itself be unreachable exactly then. A status page that shares a
        # failure domain with the things it watches is decoration.
        #
        # The disclosure is small and already public: it names services whose
        # domains resolve in public DNS anyway, and says up or down. It does
        # not expose the services themselves — the gated ones stay gated.
        status = {
          bearerAuth.enable = false;
          targets = [
            {
              port = 8085;
              peer = "gaia";
            }
          ];
        };

        # The alert sink. Ungated deliberately: the ntfy app authenticates
        # with a username and password and cannot complete an interactive
        # browser login, and gating it would also make the one service you
        # need during an outage depend on kanidm, which lives on the host
        # most likely to be the outage.
        ntfy = {
          bearerAuth.enable = false;
          targets = [
            {
              port = 8095;
              peer = "gaia";
            }
          ];
        };

        # Ungated, because grafana does its own kanidm OIDC. Gating it as
        # well would mean logging in twice, and worse: the gate answers a
        # lapsed session with a 302 to the IdP, which grafana's XHR calls
        # cannot follow — the NetworkError that took traccar down.
        grafana = {
          bearerAuth.enable = false;
          targets = endeavour 3000;
        };

        # Public, and unauthenticated by design.
        typstnique = {
          bearerAuth.enable = false;
          targets = endeavour 3030;
        };

        # The apex is deliberately absent from this list and cannot be added.
        # netbird-proxy's cluster domain *is* lvdar.nl, and management rejects
        # any service that is not a label beneath it:
        #
        #   {"message":"domain lvdar.nl requires a subdomain label","code":422}
        #
        # The reconciler retried every five minutes and logged only its generic
        # "domain or listen port already taken" guess, while the proxy answered
        # the apex with `unknown domain` and a TLS internal error — a service
        # that looked configured and was never created. It is served by this
        # host's nginx instead, via netbird.localVhosts below.
        #
        # www can be a proxy service, because it is a subdomain like any other.
        # The app answers it with a 301 to the apex.
        www = {
          bearerAuth.enable = false;
          targets = endeavour 3031;
        };

        # Open WebUI. Ungated, and for the sharper of the two reasons already
        # on this page: it is an SPA whose chat responses stream over SSE, so a
        # lapsed gate session answers a long-lived streaming request with a 302
        # the frontend cannot follow. That is the traccar NetworkError again,
        # except it would strike mid-answer. It runs its own kanidm OIDC, so
        # gating would also be a second login for the same identity.
        chat = shared 8084;

        jellyfin = shared 8096;
        immich = shared 2283;
        seerr = shared 4055;

        # A paste exists to be handed to someone, so a gate in front would
        # mean the recipient needs an account here first. Reads are open;
        # creating a pasta needs MICROBIN_UPLOADER_PASSWORD.
        bin = shared 8087;

        # Paperless runs its own kanidm OIDC, so a gate here would be the
        # same login twice.
        paperless = shared 28981;

        # Kavita runs its own kanidm OIDC, so a gate here would be the same
        # login twice — the reasoning that already covers cloud and chat.
        kavita = shared 5000;

        # The tangled knot's HTTP half. Ungated: git clients send basic auth or
        # nothing at all and cannot complete an interactive IdP redirect, the
        # same constraint that keeps the *arr suite's API consumers working.
        # Public read is public by intent; writes are authenticated by the knot
        # against ATProto identity.
        knot = shared 5555;

        # The knot's CI runner. Ungated for the same reason as the knot: the
        # appview has to reach it to register it and dispatch work, and a
        # NetBird identity check answers a lapsed session with a redirect to
        # kanidm, which no service-to-service caller can follow.
        spindle = shared 6555;

        # The ATProto PDS. Ungated for the reason every app-facing service here
        # is: XRPC clients carry their own tokens and a 302 to kanidm is a bare
        # network error to them.
        pds = shared 3001;

        # Ungated for the same reason as the rest of `shared`, plus one of its
        # own: the web UI is an SPA that talks to /api over XHR, and the
        # Traccar Manager app talks to the same API with no browser at all.
        # When the gate's session lapses those requests get a redirect to the
        # IdP rather than a 401 — which the app cannot follow and the browser
        # reports as a bare NetworkError. Traccar has its own accounts.
        traccar = shared 8082;

        # The port trackers actually report to. Traccar runs a decoder per
        # protocol across 5001-5263 and this host publishes exactly the one in
        # use — `cosmos.services.traccar.protocols` on endeavour picks it, and
        # the two have to agree.
        #
        # L4, not HTTP: a tracker opens a socket and speaks its own protocol,
        # so there is nothing to terminate TLS for or apply a CrowdSec verdict
        # to. The domain below routes nothing — the listen port does — so a
        # device pointed at traccar.lvdar.nl:5055 arrives here regardless.
        traccar-osmand = {
          domain = "traccar-osmand.lvdar.nl";
          mode = "tcp";
          listenPort = 5055;
          bearerAuth.enable = false;
          targets = endeavour 5055;
        };

        # The control page for the two servers below — and the one Minecraft
        # entry here that is GATED, which is the whole point of it. Everything
        # else on this page is either public by design or protected by the
        # game's own whitelist; this one hands out a console on a systemd unit.
        #
        # The gate is deliberately wider than the default `netbird-<name>`.
        # This service does its own per-server authorisation from the groups
        # netbird-proxy stamps on the request, and its finest-grained group is
        # per server — so gating solely on netbird-minecraft-control would mean
        # nobody could reach the page without already holding the group that
        # grants every server, and the per-server split could never do anything.
        #
        # So: any of the three gets you to the page, and
        # cosmos.services.minecraft.control.access on endeavour decides what you
        # see once you are there. Kept in sync by hand with `inAppGroups` in
        # services/kanidm.nix, den being unable to read another host's config.
        #
        # Ordinary HTTP rather than L4: it is a browser talking to nginx, so
        # there is TLS to terminate and a CrowdSec verdict worth applying, and
        # a human can complete the IdP redirect that a game client cannot.
        minecraft-control = {
          # The bare name, because this is the thing a person opens. The game
          # servers took it first and have moved to smp./hardcore., which are
          # what players type; a browser going to minecraft.lvdar.nl wants the
          # page, not a TCP socket speaking Mojang's protocol.
          domain = "minecraft.lvdar.nl";
          targets = endeavour 8086;
          bearerAuth.groups = [
            "netbird-minecraft-control"
            "netbird-minecraft-smp"
            "netbird-minecraft-hardcore"
          ];
        };

        # Minecraft. L4 for the same reason as traccar-osmand: the client
        # opens a socket and speaks Mojang's own protocol, so there is no TLS
        # to terminate and no HTTP for CrowdSec to read. The domain routes
        # nothing — the listen port does — but it still has to be unique and it
        # still has to resolve to this host, because that is the address a
        # player types.
        #
        # bearerAuth off is not a preference. A game client cannot follow a
        # browser redirect to an IdP; gating this would publish a port that
        # every Minecraft client fails to connect to. The whitelist on
        # endeavour is the access control, and it is enforced there.
        #
        # If this connects but never completes a handshake, it is the same
        # unexplained L4 failure the knot's :22 hit — see the DNAT above, which
        # is the proven way around it.
        #
        # Note the target inherits `protocol = "http"` from the helper, which
        # reads like a bug in an L4 service and is deliberately left alone:
        # traccar-osmand renders identically and works, so it is the known-good
        # shape and this is not the place to deviate from it. Setting the
        # target protocol to "tcp" is the first thing to try if this does not
        # forward — it would also be the first new lead on the knot's :22 in a
        # while, since that service had this same shape.
        minecraft-smp = {
          domain = "smp.lvdar.nl";
          mode = "tcp";
          listenPort = 25565;
          bearerAuth.enable = false;
          targets = endeavour 25565;
        };

        # The second world, and the one that explains why both cannot simply be
        # 25565: L4 routes by listen port and nothing else. Every name under
        # lvdar.nl is a wildcard onto this host's single address, and a TCP
        # connection carries no hostname for the proxy to read, so two services
        # on 25565 would be one socket with two names for it.
        #
        # An SRV record is what makes the port invisible anyway. The Java client
        # looks up _minecraft._tcp.<host> before connecting and honours the port
        # it finds, so players type a bare `hardcore.lvdar.nl` and land here:
        #
        #   _minecraft._tcp.hardcore.lvdar.nl  SRV  0 0 25566 hardcore.lvdar.nl
        #
        # That record lives in Cloudflare by hand — the wildcard covers A
        # lookups but cannot answer SRV. Without it this is still reachable, as
        # hardcore.lvdar.nl:25566 typed in full.
        #
        # The alternative would be a Velocity proxy on 25565 routing by the
        # hostname in the handshake, which is the only way to put both worlds
        # literally on the same port. It was not worth it: it makes one process
        # a dependency of both servers, and it requires turning off online-mode
        # on the backends in favour of a forwarding secret — a configuration
        # whose failure mode is anyone joining as anyone.
        minecraft-hardcore = {
          domain = "hardcore.lvdar.nl";
          mode = "tcp";
          listenPort = 25566;
          bearerAuth.enable = false;
          targets = endeavour 25566;
        };

        # Simple Voice Chat's audio, for the hardcore server only. UDP and a
        # separate service because voice is a second socket, not part of the
        # game's TCP stream — a client joins over 25566 and is then told to
        # speak to this port.
        #
        # 24454 is the mod's default and it is deliberately unchanged: the
        # client discovers the port from the server, so the number matters only
        # to whoever is reading firewall rules. Only the hardcore world runs the
        # mod, so nothing collides.
        #
        # If voice breaks while the game still works, this is the thing to
        # check — an unreachable voice port is silent by design, showing
        # players "voice chat unavailable" rather than failing the connection.
        minecraft-hardcore-voice = {
          domain = "hardcore-voice.lvdar.nl";
          mode = "udp";
          listenPort = 24454;
          bearerAuth.enable = false;
          targets = endeavour 24454;
        };

        suwayomi.targets = endeavour 8080;
        sabnzbd.targets = endeavour 6336;

        # The *arr suite. These sit on the host rather than in the VPN
        # namespace — only the download clients are confined — so they are
        # reached directly. Each ships an API key rather than a login, so the
        # identity check in front is the only thing between them and the
        # internet.
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
