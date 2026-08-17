# home.catt — throw a video at a Chromecast-capable device from the shell.
#
# `catt cast <file-or-url>` and `catt cast_site <url>`, plus pause/seek/volume
# against whatever is playing. It talks the Chromecast protocol directly, so the
# device does the fetching and decoding and this machine is only the remote.
#
# Two things about it that are easy to trip over, neither of which is a bug:
#
#   * discovery is mDNS on the local link, so the device has to be on the same
#     LAN as this laptop. Not the NetBird mesh — and since the mesh now gives a
#     non-fleet peer nothing but DNS (see cosmos.services.netbird.mesh in
#     hosts/gaia.nix), enrolling a TV box would not help even if it could.
#   * casting a local *file* starts a little web server here and hands the
#     device a URL pointing back at this machine, so playback stops when the
#     laptop sleeps. Casting a URL the device can reach on its own — a Jellyfin
#     stream, say — has no such tie.
#
# For watching the library on a TV this is the second-best answer anyway: the
# Jellyfin app on the device plays directly and keeps its own transcoding
# decisions. catt earns its place for the one-off — a file that is not in the
# library, or a video in a browser tab.
{...}: {
  den.aspects.home.catt.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.catt];

    # catt remembers aliases and the last device used, so without this every
    # new shell starts by rescanning the network for something it already knew.
    cosmos.system.impermanence.persist.directories = [".config/catt"];
  };
}
