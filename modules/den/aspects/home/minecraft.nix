# home.minecraft — PrismLauncher + the MCSR toolchain (reuses the _waywall.nix
# part file and the local pkgs.mcsr.* packages).
{...}: {
  den.aspects.home.minecraft.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption;
    inherit (lib.lists) optionals;

    cfg = config.cosmos.gaming.launchers.minecraft;
  in {
    imports = [../../../home/gaming/launchers/minecraft/_waywall.nix];

    options.cosmos.gaming.launchers.minecraft.mcsr.enable = mkEnableOption "mcsr setup";

    config = {
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
          pkgs.mcsr.modcheck
          pkgs.mcsr.ninjabrain-bot
        ];

      cosmos.gaming.launchers.minecraft.waywall = {
        enable = cfg.mcsr.enable;
        config = {
          enableWaywork = true;
          enableFloating = true;
          programs = [pkgs.mcsr.ninjabrain-bot];
          files.eye_overlay = ../../../home/gaming/launchers/minecraft/eye-overlay.png;
          text =
            ''
              local resolution = { w = 1920, h = 1080 }
            ''
            + builtins.readFile ../../../home/gaming/launchers/minecraft/waywall.lua;
        };
      };
    };
  };
}
