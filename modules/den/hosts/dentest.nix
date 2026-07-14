# THROWAWAY mechanism-proof host — verifies den produces a buildable nixos
# toplevel with our overlays (pkgs.stable / local pkgs) resolving. Deleted once
# the real hosts are wired.
{...}: {
  den.hosts.x86_64-linux.dentest = {};

  den.aspects.dentest.nixos = {pkgs, ...}: {
    system.stateVersion = "25.11";
    boot.loader.grub.enable = false;
    fileSystems."/" = {
      device = "/dev/fake";
      fsType = "auto";
    };
    # prove the overlays reached the host:
    environment.systemPackages = [
      pkgs.stable.hello
      pkgs.mcrl2
    ];
  };
}
