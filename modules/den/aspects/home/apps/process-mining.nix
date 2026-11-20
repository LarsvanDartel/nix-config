# home.process-mining — ProM Lite and CPN IDE for the 2AMI10 course
{...}: {
  den.aspects.home.process-mining.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.prom-lite pkgs.cpn-ide];

    cosmos.system.impermanence.persist.directories = [
      ".local/share/prom-lite"
      ".local/share/cpn-ide"
    ];
  };
}
