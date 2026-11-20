# services.pds — single-user self-hosted ATProto Personal Data Server.
{den, ...}: let
  # Option default and netbird-service target (see services/netbird.nix).
  defaultPort = 3001;
in {
  den.aspects.services.pds = {
    includes = [den.aspects.services.netbird.client];

    # Ungated: XRPC clients carry their own tokens and can't follow a NetBird 302 to kanidm.
    netbird-service = {host, ...}: {
      pds = {
        bearerAuth.enable = false;
        targets = [
          {
            peer = host.name;
            port = defaultPort;
          }
        ];
      };
    };

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
          default = defaultPort;
          description = ''
            Not the module's default of 3000: grafana already has that on this
            host (services/grafana.nix). Reached over the mesh by gaia's
            netbird-proxy, never bound publicly.
          '';
        };
      };

      config = {
        # PDS_JWT_SECRET, PDS_ADMIN_PASSWORD and the PLC rotation key, which proves control of the
        # DID and cannot be regenerated: keep it in a password manager too.
        sops.secrets."keys/pds/env" = {};

        services.bluesky-pds = {
          enable = true;
          settings = {
            PDS_HOSTNAME = cfg.hostname;
            PDS_PORT = cfg.port;
          };
          environmentFiles = [config.sops.secrets."keys/pds/env".path];

          pdsadmin.enable = true;
        };

        # On the SSD, not /tank: the one thing here whose latency a phone notices.
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
