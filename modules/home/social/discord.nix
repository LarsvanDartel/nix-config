{...}: {
  flake.modules.homeManager.desktop = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/discord"];

    home.packages = with pkgs; [
      discord
    ];
  };
}
