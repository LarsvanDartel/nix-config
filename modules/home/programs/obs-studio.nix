{...}: {
  flake.modules.homeManager.obs-studio = {
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
        example = lib.literalExpression "with pkgs.obs-studio-plugins; [obs-backgroundremoval obs-pipewire-audio-capture]";
        description = "OBS Studio plugins to install. See pkgs.obs-studio-plugins.";
      };

      cudaSupport = mkOption {
        type = bool;
        default = false;
        description = ''
          Build OBS with NVENC support so the NVIDIA GPU's hardware encoder shows
          up under Output. Requires the NVIDIA driver at runtime. This triggers a
          from-source rebuild of OBS (and its CUDA-enabled ffmpeg), so it is off
          by default; prefer VAAPI (obs-vaapi plugin) on machines with a usable
          iGPU.
        '';
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
