# home.simplelogin — SimpleLogin alias CLI
{...}: {
  den.aspects.home.simplelogin.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/simplelogin-cli"];
    home.packages = [pkgs.simplelogin-cli];
  };
}
