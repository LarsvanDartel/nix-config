# services.netbird-gewis — second NetBird client on GEWIS's control plane; log in once with `netbird-gewis up`.
{den, ...}: {
  den.aspects.services.netbird-gewis = {
    includes = [den.aspects.services.netbird.client];

    # Host-scope homeManager is dropped by den; to-users is the edge into homes.
    provides.to-users.homeManager.cosmos.cli.shells.zsh.aliases.nbg = "netbird-gewis";

    nixos = {config, ...}: let
      client = config.services.netbird.clients.gewis;
      url = {
        Scheme = "https";
        Host = "nb.gewis.nl:443";
        Path = "";
      };
    in {
      # openresolv gives resolv.conf to whichever agent starts last; resolved
      # gives each agent split DNS on its own link.
      services.resolved.enable = true;

      services.netbird.clients.gewis = {
        port = 51821;
        # Root like wt0; hardened gates the CLI socket behind a group.
        hardened = false;

        config = {
          ManagementURL = url;
          AdminURL = url;
        };

        # Moves state NetBird hardcodes out of wt0's way; see docs/src/notes/services-netbird-gewis.md#two-agents-on-one-host.
        environment = {
          NB_NFTABLES_TABLE = "netbird-gewis";
          NB_USE_LEGACY_ROUTING = "true";
          NB_FWMARK_BASE = "0x1be00";
        };
      };

      cosmos.system.impermanence.persist.directories = [
        {
          directory = client.dir.state;
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };
  };
}
