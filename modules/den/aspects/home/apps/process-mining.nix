# home.process-mining — the 2AMI10 course tools.
#
# Both keep their state under ~/.local/share, and for ProM that is not a cache
# you can afford to lose: it downloads its Lite package set (~400 MB) on first
# run and re-downloads the lot whenever the directory is gone, which on a
# root-rollback host is every boot.
{...}: {
  den.aspects.home.process-mining.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.prom-lite pkgs.cpn-ide];

    cosmos.system.impermanence.persist.directories = [
      ".local/share/prom-lite"
      ".local/share/cpn-ide"
    ];
  };
}
