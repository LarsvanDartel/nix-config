# home.network-displays — mirror this screen onto a Miracast sink (a TV, or an
# Android TV box that still speaks it).
#
# The counterpart to home.catt rather than a replacement: catt hands a device a
# URL and steps out of the way, which is the better answer whenever the thing
# being watched *has* a URL. This is for the case that has none — a slide deck,
# a terminal, a game — where the picture itself has to travel.
#
# Explicitly not Chromecast. Google Cast screen mirroring is a closed protocol
# with no open implementation, so catt cannot do it and neither can anything
# else here; Miracast is a different standard that happens to be supported by
# many of the same devices. Whether a given box accepts it is a property of that
# box, and plenty of Android TV hardware has quietly dropped it.
#
# How it works, because the failure modes only make sense with the shape in
# mind: wpa_supplicant negotiates a Wi-Fi Direct group with the sink,
# NetworkManager configures that link and shares it with dnsmasq, the sink takes
# a DHCP lease and then opens an RTSP connection *back* to this machine on 7236.
# So the traffic is inbound on an interface that did not exist a second earlier,
# which is what makes the firewall rules in hosts/voyager.nix necessary and why
# they are the first thing to suspect.
#
# Prerequisites checked before adding this, both of which hold on voyager:
#   * the chipset advertises P2P-GO and P2P-client (`iw list`), without which
#     there is no Wi-Fi Direct at all;
#   * wpa_supplicant is the backend, not iwd, which has no P2P support.
{...}: {
  den.aspects.home.network-displays.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.gnome-network-displays];
  };
}
