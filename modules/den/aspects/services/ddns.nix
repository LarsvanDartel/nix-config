# services.ddns — publish this host's public address as a name.
#
# Exists for gaia's crowdsec whitelist: the home address is dynamic, and a
# checked-in literal drifts into whitelisting whoever the ISP hands the
# address to next. crowdsec resolves names for exactly this (s01-whitelist
# postoverflow, services/crowdsec.nix); this module keeps the name true.
# Runs on endeavour, the host actually behind the home connection — gaia
# only sees that address as a source IP.
#
# A crowdsec ban is not a 403: the bouncer drops in nftables, so it
# black-holes the WireGuard handshake too — losing the mesh from home loses
# the path to the fix.
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
        default = "keys/cloudflare/dns";
        description = ''
          sops key holding the Cloudflare API token.

          The same key acme reads, and deliberately so now: sops secrets are
          per host, so `keys/cloudflare/dns` means "the Cloudflare token this
          machine can use" rather than one shared credential. Each host holds
          its own, scoped to the address it actually calls from, and a token
          leaked from one still cannot act as another.

          This used to be a separate `ddns` key, because endeavour's copy of
          the acme token was pinned to gaia's address and refused from home —
          so the host carried two tokens, one of which silently could not work.
          That also broke acme on endeavour, which reads the acme key and had
          no usable token in it. One per host fixes both.

          Needs Zone:DNS:Edit on the zone, which covers this and acme's DNS-01.
        '';
      };
    };

    config = mkIf cfg.enable {
      sops.secrets.${cfg.secret} = {};

      # Upstream orders this After=network.target only. On the 2026-08-24
      # reboot it ran before DNS answered, failed, and (Restart=no oneshot)
      # was not retried until the timer.
      systemd.services.cloudflare-dyndns = {
        wants = ["network-online.target"];
        after = ["network-online.target" "nss-lookup.target"];
      };

      services.cloudflare-dyndns = {
        enable = true;
        apiTokenFile = config.sops.secrets.${cfg.secret}.path;
        inherit (cfg) domains;
        ipv4 = true;
        # The v6 prefix rotates independently of the v4 address — a stale AAAA
        # would send traffic nowhere; crowdsec matches the v4 source address.
        ipv6 = false;
        proxied = false;
        # Often enough to matter after a re-address, rarely enough to stay well
        # inside Cloudflare's rate limits.
        frequency = "*:0/15";
      };
    };
  };
}
