# home.catt — cast a video to a Chromecast device from the shell
{...}: {
  den.aspects.home.catt = {
    homeManager = {pkgs, ...}: {
      home.packages = [pkgs.catt];

      cosmos.system.impermanence.persist.directories = [".config/catt"];
    };

    # 5353: mDNS replies (dropped = empty scan; same LAN only, not the mesh). 45114: the local-file
    # cast server, so a cast local file plays only while this machine is awake.
    provides.to-hosts.nixos = {...}: {
      networking.firewall.allowedUDPPorts = [5353];
      networking.firewall.allowedTCPPorts = [45114];
    };
  };
}
