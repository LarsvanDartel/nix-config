# services.netbird-gewis — a second NetBird client on GEWIS's control plane
# (nb.gewis.nl), alongside the fleet mesh on wt0. Login is interactive, once:
# `netbird-gewis up` (GEWIS SSO).
#
# Two agents on one host collide on state NetBird hardcodes (checked against
# 0.80.0); each env var below moves this one out of wt0's way:
# - nftables table `netbird`: every agent deletes it on start, so the two
#   would wipe each other's ACLs (and the ACL watchdog would restart wt0 into
#   the fight).
# - routing table 7120 + its ip rules: flushed on every start, which drops
#   wt0's routes (endeavour's LAN). Legacy routing puts GEWIS routes in main
#   instead, which wt0's `lookup main suppress_prefixlength 0` rule reads first.
# - fwmarks: a separate range so neither table's mark matches act on the
#   other's packets.
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
      # openresolv's `resolvconf -x` is exclusive per agent: whichever starts
      # last owns resolv.conf and the other mesh's names stop resolving.
      # resolved gives each agent split DNS on its own link.
      services.resolved.enable = true;

      services.netbird.clients.gewis = {
        port = 51821;
        # Root like wt0; hardened gates the CLI socket behind a group.
        hardened = false;

        config = {
          ManagementURL = url;
          AdminURL = url;
        };

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
