# home.catt — throw a video at a Chromecast-capable device from the shell.
#
# Traps: discovery is mDNS on the local link, so the device must be on the
# same LAN — not the NetBird mesh, which gives a non-fleet peer nothing but
# DNS anyway (cosmos.services.netbird.mesh, hosts/gaia.nix). Casting a local
# *file* starts a web server here and hands the device a URL back to this
# machine, so playback stops when the laptop sleeps; casting a URL the device
# can reach (a Jellyfin stream) has no such tie.
{...}: {
  den.aspects.home.catt.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.catt];

    cosmos.system.impermanence.persist.directories = [".config/catt"];
  };
}
