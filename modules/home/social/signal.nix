{...}: {
  flake.modules.homeManager.desktop = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [
      ".config/Signal"
    ];

    home.packages = with pkgs; [
      signal-desktop
    ];
  };
}
