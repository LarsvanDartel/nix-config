# gaia (x86_64 server). den-produced.
#
# Generate the facter report on gaia and commit:
#   sudo nixos-facter -o modules/den/hosts/_facter/gaia.facter.json
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.gaia = {
    users.nixos = {};
    meshAddress = "100.68.38.155";
    server = true;
    # Its public name, deliberately: gaia runs the mesh control plane, so it
    # must be reachable for deploys when the mesh is broken.
    deployAddress = "lvdar.nl";
    sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILT7WtA9mgRcwDlP5Cw6ndr4SjFT1Wfk8idaf8fEA3Q5";
  };

  den.aspects.gaia = {
    includes = with den.aspects; [
      core.boot
      core.impermanence
      services.netbird
      services.crowdsec
      services.ntfy
      services.stalwart
      services.unbound
      services.gatus
      services.alloy
      services.restic
      # A broken netbird-proxy takes comin's update path with it; recovery
      # is deploy-rs over :2222, which is why that stays.
      services.comin
    ];

    nixos = {
      config,
      lib,
      ...
    }: let
      endeavourMesh = den.hosts.x86_64-linux.endeavour.meshAddress;
      denHosts = lib.attrNames (lib.mergeAttrsList (lib.attrValues den.hosts));
    in {
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

      # endeavour, where firefly/traccar relay through gaia.nb.lvdar.nl:2525;
      # hand-synced with services/firefly.nix and services/traccar.nix.
      cosmos.services.stalwart.relayClients = [endeavourMesh];

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
          "/persist/var/lib/stalwart"
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

        # Live SQLite store and live RocksDB — see quiesceServices in
        # services/restic.nix. Inbound senders retry during the stop.
        quiesceServices = ["netbird-management.service" "stalwart.service"];
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
            destination = "${endeavourMesh}:2222";
            proto = "tcp";
          }
        ];
        extraCommands = ''
          iptables -t nat -A POSTROUTING -d ${endeavourMesh} -p tcp --dport 2222 -j MASQUERADE
          iptables -A FORWARD -d ${endeavourMesh} -p tcp --dport 2222 -j ACCEPT
        '';
        extraStopCommands = ''
          iptables -t nat -D POSTROUTING -d ${endeavourMesh} -p tcp --dport 2222 -j MASQUERADE || true
          iptables -D FORWARD -d ${endeavourMesh} -p tcp --dport 2222 -j ACCEPT || true
        '';
      };

      # DNAT skips INPUT, but the port must still be open.
      networking.firewall.allowedTCPPorts = [22];

      cosmos.system.journald.maxUse = "512M";

      # Via nginx, not netbird-proxy: management needs kanidm to start and
      # the proxy needs management.
      cosmos.services.netbird.oidc.idp = {
        domain = "auth.lvdar.nl";
        upstream = "https://${endeavourMesh}:8443";
      };

      # netbird-proxy can't serve the apex (see services/site.nix, which
      # publishes www). Ungated: a public blog.
      cosmos.services.netbird.localVhosts."lvdar.nl".upstream = "http://${endeavourMesh}:3031";

      # comin pulls, so no credential here grants anything on the fleet.
      cosmos.services.comin.repository = "https://knot.lvdar.nl/did:plc:a3erncqfgkcxu3yl6fpjfmwf";

      # Dotted names probe as written, bare labels as subdomains. Explicit,
      # not derived from cosmos.services.netbird.services: the order is the
      # status page's, lvdar.nl and auth are not proxy services, and not
      # every published service is worth probing.
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
        "vault"
      ];

      # Ad-blocking DNS follows roaming devices; gaia is the fallback.
      cosmos.services.netbird.dnsPeers = ["endeavour" "gaia"];

      # Non-fleet peers get DNS only. panther deliberately absent: it only
      # uses published names. `enforce` retires All -> All; getting it wrong
      # takes out SSH to everything at once.
      cosmos.services.netbird.mesh = {
        fleet = denHosts;
        resolvers = [
          "endeavour"
          "gaia"
        ];
        enforce = true;
      };

      # panther is a phone with no shell.
      cosmos.services.netbird.sshPeers = denHosts;

      system.stateVersion = "24.11";
    };
  };
}
