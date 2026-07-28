# home.pangolin (pangolin-cli)
{...}: {
  den.aspects.home.pangolin.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/pangolin"];
    home.packages = [pkgs.pangolin-cli];
  };
}
