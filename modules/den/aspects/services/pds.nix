# services.pds — a self-hosted ATProto Personal Data Server.
#
# The point of this is ownership of an identity rather than of a service. A PDS
# holds the repository of signed records behind an ATProto account: posts,
# follows, and — once services/tangled.nix is running — the issues and pull
# requests that Tangled stores as records rather than rows. Running it here
# means the account is addressed by a domain that is already ours instead of by
# a username on somebody's server.
#
# Single-user by design. The handle sits directly under lvdar.nl, which the
# existing *.lvdar.nl wildcard in services/acme.nix already covers, so this
# needs no certificate work at all. Hosting handles for other people would mean
# a second-level wildcard (*.pds.lvdar.nl) — wildcards match a single label, so
# *.lvdar.nl does not cover it — and that is a deliberate non-goal here.
#
# Ungated at the edge, like immich and traccar and for the same reason: ATProto
# clients speak XRPC over HTTP and authenticate with their own tokens. A NetBird
# identity check in front answers a lapsed session with a 302 to kanidm, which
# no app can follow — it surfaces as a bare network error.
{den, ...}: {
  den.aspects.services.pds = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.pds;
    in {
      options.cosmos.services.pds = {
        hostname = mkOption {
          type = str;
          default = "pds.lvdar.nl";
          description = ''
            The PDS's own name, which is also the service DID's domain.

            Handles are separate from this and live directly under lvdar.nl.
            Changing it after an account exists is not a rename — the DID
            document points here, so it is a migration.
          '';
        };

        port = mkOption {
          type = port;
          default = 3001;
          description = ''
            Not the module's default of 3000: grafana already has that on this
            host (services/grafana.nix). Reached over the mesh by gaia's
            netbird-proxy, never bound publicly.
          '';
        };
      };

      config = {
        # PDS_JWT_SECRET, PDS_ADMIN_PASSWORD and the PLC rotation key. The
        # rotation key is the one that cannot be regenerated: it is what proves
        # control of the DID, so losing it means losing the identity even with
        # every byte of data intact. It belongs in a password manager as well as
        # here, exactly like the restic repository password.
        sops.secrets."keys/pds/env" = {};

        services.bluesky-pds = {
          enable = true;
          settings = {
            PDS_HOSTNAME = cfg.hostname;
            PDS_PORT = cfg.port;
          };
          environmentFiles = [config.sops.secrets."keys/pds/env".path];

          # Account creation, invites and the eventual `goat` migration all
          # happen from the shell on this host.
          pdsadmin.enable = true;
        };

        # Static `pds` user with a plain StateDirectory, so this is the ordinary
        # persist shape rather than the /var/lib/private EBUSY case that ntfy
        # hit. On the SSD rather than /tank: it is small, and it is the one
        # thing here whose latency a phone notices.
        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/pds";
            user = "pds";
            group = "pds";
            mode = "0755";
          }
        ];

        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
