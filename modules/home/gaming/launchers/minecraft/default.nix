{...}: {
  flake.modules.homeManager.minecraft = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption;
    inherit (lib.lists) optionals;

    cfg = config.cosmos.gaming.launchers.minecraft;
  in {
    # The waywall sub-module keeps its own internal enable toggle; it is loaded
    # here (as an import-tree-ignored part-file) rather than being its own
    # top-level feature.
    imports = [./_waywall.nix];

    options.cosmos.gaming.launchers.minecraft = {
      mcsr.enable = mkEnableOption "mcsr setup";
    };

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
  };
}
