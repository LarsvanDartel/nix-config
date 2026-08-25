# services.ddns — publish this host's public address as a name.
#
# Exists for one reason: gaia's crowdsec whitelist needs to know the home
# connection, and a checked-in literal cannot. hosts/gaia.nix carried
# `whitelistIps = ["86.86.217.11"]` with a comment admitting it is "dynamic, so
# it will drift" — and when it does it stops protecting this household and
# starts protecting whoever the ISP hands the address to next. The comment
# claimed the `lvdar.nl` entry in whitelistFqdns was "the durable half", but
# lvdar.nl resolves to gaia, not to home, so nothing covered this.
#
# crowdsec already resolves names for exactly this purpose
# (services/crowdsec.nix, the s01-whitelist postoverflow, one lookup per alert
# rather than per event). Giving it a name that tracks the address is the whole
# fix; this is the half that keeps the name true.
#
# Runs on endeavour rather than gaia because endeavour is the host that is
# actually behind the home connection. gaia sees that address only as a source
# IP on inbound connections, which is not something it can publish.
#
# The whitelist matters because crowdsec's bouncer drops in nftables, not in
# nginx: a ban on the home address does not merely return 403, it black-holes
# the WireGuard handshake too. Losing the mesh from home is the one failure
# where the fix and the path to the fix disappear together.
{...}: {
  den.aspects.services.ddns.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) listOf str;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.services.ddns;
  in {
    options.cosmos.services.ddns = {
      enable = mkEnableOption "publishing this host's public IPv4 as a DNS name";

      domains = mkOption {
        type = listOf str;
        default = ["home.lvdar.nl"];
        description = ''
          Names to point at this host's public address. The record does not have
          to exist first: cloudflare-dyndns creates it when get_record_id misses
          (updater.py), so the token needs create as well as edit — Zone:DNS:Edit
          covers both.
        '';
      };

      secret = mkOption {
        type = str;
        default = "keys/cloudflare/ddns";
        description = ''
          sops key holding the Cloudflare API token.

          Deliberately NOT keys/cloudflare/dns, which acme uses: that token is
          restricted to gaia's address and would be refused from here. This one
          needs Zone:DNS:Edit on lvdar.nl and must be usable from the home
          connection. Keeping them separate also means a token leaked from
          either host cannot rewrite the other's records.
        '';
      };
    };

    config = mkIf cfg.enable {
      sops.secrets.${cfg.secret} = {};

      # Upstream orders this After=network.target, which only means the network
      # stack has been configured — not that a route exists or that DNS answers.
      # On the reboot of 2026-08-24 it ran anyway, failed to reach the ipify API,
      # and the failure notification then failed too because ntfy.lvdar.nl did
      # not resolve yet. It is a Restart=no oneshot, so nothing retried it until
      # the timer came round fifteen minutes later.
      systemd.services.cloudflare-dyndns = {
        wants = ["network-online.target"];
        after = ["network-online.target" "nss-lookup.target"];
      };

      services.cloudflare-dyndns = {
        enable = true;
        apiTokenFile = config.sops.secrets.${cfg.secret}.path;
        inherit (cfg) domains;
        ipv4 = true;
        # The home connection's v6 prefix is delegated and rotates independently
        # of the v4 address; publishing a stale AAAA would send traffic nowhere.
        # crowdsec matches on the source address of the connection, which for
        # this purpose is v4.
        ipv6 = false;
        proxied = false;
        # Often enough to matter after a re-address, rarely enough to stay well
        # inside Cloudflare's rate limits.
        frequency = "*:0/15";
      };
    };
  };
}
