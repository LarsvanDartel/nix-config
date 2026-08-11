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
    ];

    nixos = {...}: {
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
      ];

      cosmos.system = {
        boot = {
          legacy = true;
          grub-device = "/dev/sda";
        };
        impermanence.device = "/dev/disk/by-label/nixos";
      };

      # The home connection, so a bad afternoon of poking at these services
      # cannot lock the only administrator out of the only way in. Dynamic, so
      # it will drift; the lvdar.nl entry in whitelistFqdns is the durable half.
      cosmos.services.crowdsec.whitelistIps = ["86.86.217.11"];

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

        jellyfin = shared 8096;
        immich = shared 2283;
        seerr = shared 4055;

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
