# services.minecraft.packs — packs.lvdar.nl: every packwiz pack in the
# modpacks input, for the packwiz-installer in each player's instance.
#
# Served from the deployed input, not the knot, so players sync exactly the
# revision the servers run. The URL is baked into every instance zip
# (`baseUrl` in the modpacks flake): moving it strands those instances.
{den, ...}: let
  # Option default and netbird-service target (see services/netbird.nix).
  defaultPort = 8089;
in {
  den.aspects.services.minecraft.packs = {
    includes = [den.aspects.services.nginx den.aspects.services.netbird.client];

    # Open: packwiz-installer cannot follow an IdP redirect, and a pack holds
    # nothing beyond public mod URLs and configs.
    netbird-service = {host, ...}: {
      minecraft-packs = {
        domain = "packs.lvdar.nl";
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
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port;

      cfg = config.cosmos.services.minecraft.packs;

      root = pkgs.linkFarm "minecraft-packs" (lib.mapAttrs (_: p: p.src) pkgs.modpacks);
    in {
      options.cosmos.services.minecraft.packs.port = mkOption {
        type = port;
        default = defaultPort;
      };

      config = {
        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        services.nginx.virtualHosts.minecraft-packs = {
          listen = [
            {
              addr = "0.0.0.0";
              inherit (cfg) port;
            }
          ];
          inherit root;

          # Every store path has mtime 1970, so Last-Modified and the
          # mtime-based ETag survive a pack update unchanged: a conditional
          # request would get a 304 and keep the old index. Always send it.
          extraConfig = ''
            ${config.cosmos.services.netbird.client.proxyRealIp}
            etag off;
            if_modified_since off;
            add_header Cache-Control "no-cache";
          '';
        };
      };
    };
  };
}
