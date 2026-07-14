{...}: {
  flake.modules.homeManager.pangolin = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/pangolin"];
    home.packages = [pkgs.pangolin-cli];
  };
}
