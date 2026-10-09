# home.process-mining — the 2AMI10 course tools. ~/.local/share/prom-lite is
# persisted: ProM Lite re-downloads ~400 MB whenever it is gone.
{...}: {
  den.aspects.home.process-mining.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.prom-lite pkgs.cpn-ide];

    cosmos.system.impermanence.persist.directories = [
      ".local/share/prom-lite"
      ".local/share/cpn-ide"
    ];
  };
}
