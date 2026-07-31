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
      services.typstnique
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

      # kanidm is served by nginx here rather than by netbird-proxy, because
      # management cannot start without it and the proxy cannot route without
      # management. The mesh address is a literal for the same reason the ports
      # below are: den cannot read another host's config. NetBird assigns it at
      # enrollment and keeps it, so it only changes if endeavour is re-enrolled.
      # typstnique runs here rather than on a peer, but is published the same
      # way, so the proxy still has to be able to reach it over the mesh.
      cosmos.services.netbird.client.exposedPorts = [3030];

      cosmos.services.netbird.oidc.idp = {
        domain = "auth.lvdar.nl";
        upstream = "https://100.68.151.172:8443";
      };

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

        # Public, and on this host rather than endeavour.
        typstnique = {
          bearerAuth.enable = false;
          targets = [
            {
              peer = "gaia";
              port = 3030;
            }
          ];
        };

        jellyfin = shared 8096;
        immich = shared 2283;
        seerr = shared 4055;

        traccar.targets = endeavour 8082;
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
