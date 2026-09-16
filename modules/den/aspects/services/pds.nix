# services.pds — a self-hosted ATProto Personal Data Server.
#
# Single-user by design: the handle sits under lvdar.nl, covered by the
# existing wildcard in services/acme.nix. Hosting others' handles would need
# *.pds.lvdar.nl (wildcards match a single label) — a deliberate non-goal.
#
# Ungated at the edge like immich and traccar: ATProto clients authenticate
# with their own tokens and cannot follow a NetBird 302 to kanidm.
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
        # PDS_JWT_SECRET, PDS_ADMIN_PASSWORD, PLC rotation key. The rotation
        # key proves control of the DID and cannot be regenerated — losing it
        # loses the identity; it belongs in a password manager too.
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

        # Static `pds` user with a plain StateDirectory — the ordinary persist
        # shape, not the /var/lib/private EBUSY case ntfy hit. On the SSD, not
        # /tank: the one thing here whose latency a phone notices.
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
