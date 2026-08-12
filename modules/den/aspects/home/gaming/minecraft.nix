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
    imports = [./_minecraft/waywall.nix];

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
            # graalvm-21 is the speedrunning JDK and stays first — the MCSR
            # toolchain below is built around it and 1.16.1 wants a Java of
            # that era. jdk25 is here for the other direction: Minecraft 26.2
            # is compiled for Java 25 (class file version 69), so a launcher
            # that only offers 21 cannot start the current game at all. Prism
            # picks per instance, so both being present is the whole fix.
            jdks = [
              pkgs.mcsr.graalvm-21
              pkgs.jdk25
            ];
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
          files.eye_overlay = ./_minecraft/eye-overlay.png;
          text =
            ''
              local resolution = { w = 1920, h = 1080 }
            ''
            + builtins.readFile ./_minecraft/waywall.lua;
        };
      };
    };
  };
}
