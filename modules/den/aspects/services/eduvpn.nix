# services.eduvpn — the eduVPN linux client, plus the two pieces of system
# configuration it needs to work here at all. Voyager-only: it is a client for
# TU/e's campus VPN, and no server has any use for it.
#
# The GUI drives NetworkManager directly — it writes a `eduVPN` WireGuard
# profile on every connect and deletes it on disconnect — so the user only
# needs the networkmanager group, which the primary-user battery already
# grants. Nothing here runs as a service. The persist dirs are `home.eduvpn`,
# mirroring how `home.steam` pairs with roles.gaming.
{...}: {
  den.aspects.services.eduvpn = {
    nixos = {pkgs, ...}: {
      environment.systemPackages = [pkgs.eduvpn-client];

      # Strict reverse-path filtering breaks any full-tunnel VPN that routes via
      # a policy rule, which here means eduvpn's non-split profile.
      #
      # The nixos rpfilter rule sits in mangle PREROUTING with `--validmark`, so
      # it repeats the route lookup using the packet's fwmark. A reply arriving
      # on the wireless interface has mark 0, and eduvpn's `not from 0.0.0.0/0
      # fwmark <wg mark>` rule therefore sends that lookup into eduvpn's own
      # table, whose default route points back down the tunnel. oif never
      # matches the interface the packet came in on, so the packet is dropped —
      # taking the WireGuard handshake response with it, and the proxyguard TCP
      # fallback after it. Only the split profile survived, because its table
      # holds prefixes rather than a default and the lookup falls through to
      # main.
      #
      # Loose only asks that a route to the source exist at all, which is the
      # right question on a machine with more than one routing table.
      networking.firewall.checkReversePath = "loose";
    };
  };
}
