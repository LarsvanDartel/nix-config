# home.obs-studio (+ plugins/cudaSupport options)
{...}: {
  den.aspects.home.obs-studio.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf package bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.programs.obs-studio;
  in {
    options.cosmos.programs.obs-studio = {
      plugins = mkOption {
        type = listOf package;
        default = [];
        description = "OBS Studio plugins to install.";
      };
      cudaSupport = mkOption {
        type = bool;
        default = false;
        description = "Build OBS with NVENC support (from-source rebuild).";
      };
    };

    config = {
      programs.obs-studio = {
        enable = true;
        inherit (cfg) plugins;
        package = mkIf cfg.cudaSupport (pkgs.obs-studio.override {cudaSupport = true;});
      };
      cosmos.system.impermanence.persist.directories = [".config/obs-studio"];
    };
  };
}
