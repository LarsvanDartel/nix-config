{...}: {
  flake.modules.homeManager.simplelogin = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/simplelogin-cli"];
    home.packages = [pkgs.simplelogin-cli];
  };
}
