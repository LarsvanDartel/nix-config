{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.lists) optionals;

  cfg = config.cosmos.gaming.launchers.minecraft;
in {
  imports = [./waywall.nix];

  options.cosmos.gaming.launchers.minecraft = {
    enable = mkEnableOption "minecraft launcher";
    mcsr.enable = mkEnableOption "mcsr setup";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".local/share/PrismLauncher"];

    home.packages =
      [
        (pkgs.prismlauncher.override {
          additionalLibs = [
            pkgs.jemalloc
            pkgs.libxtst
            pkgs.libxkbcommon
            pkgs.libxt
            pkgs.libxinerama
          ];
          jdks = [pkgs.mcsr.graalvm-21];
        })
      ]
      ++ optionals cfg.mcsr.enable [
        pkgs.mcsr.ninjabrain-bot
      ];

    cosmos.gaming.launchers.minecraft.waywall = {
      enable = cfg.mcsr.enable;
      config = {
        enableWaywork = true;
        enableFloating = true;
        programs = [pkgs.mcsr.ninjabrain-bot];
        files = {
          eye_overlay = ./eye-overlay.png;
        };

        text =
          ''
            local resolution = { w = 1920, h = 1080 }
          ''
          + builtins.readFile ./waywall.lua;
      };
    };
  };
}
