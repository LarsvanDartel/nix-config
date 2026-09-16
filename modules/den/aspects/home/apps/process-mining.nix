# home.process-mining — the 2AMI10 course tools. ProM Lite re-downloads its
# ~400 MB package set whenever ~/.local/share/prom-lite is gone — every boot
# on a root-rollback host — so it is persisted, not cached.
{...}: {
  den.aspects.home.process-mining.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.prom-lite pkgs.cpn-ide];

    cosmos.system.impermanence.persist.directories = [
      ".local/share/prom-lite"
      ".local/share/cpn-ide"
    ];
  };
}
