# home.catt — throw a video at a Chromecast-capable device from the shell.
#
# Traps: discovery is mDNS, so the device must be on the same LAN (not the
# mesh). Casting a local file serves it from here, so playback stops on sleep.
{...}: {
  den.aspects.home.catt = {
    homeManager = {pkgs, ...}: {
      home.packages = [pkgs.catt];

      cosmos.system.impermanence.persist.directories = [".config/catt"];
    };

    # 5353: mDNS replies (dropped = empty scan). 45114: the local-file cast
    # server (without it the video never starts).
    provides.to-hosts.nixos = {...}: {
      networking.firewall.allowedUDPPorts = [5353];
      networking.firewall.allowedTCPPorts = [45114];
    };
  };
}
