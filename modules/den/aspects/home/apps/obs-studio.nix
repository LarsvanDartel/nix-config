# home.obs-studio (+ plugins/cudaSupport/virtualAudio options)
{...}: {
  den.aspects.home.obs-studio.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) listOf package bool str;
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

      virtualAudio = {
        enable =
          mkEnableOption ''
            a virtual microphone to pair with the virtual camera.

            The virtual camera is v4l2loopback, and V4L2 carries no audio — the
            kernel API has no concept of it — so a program picking up "OBS
            Virtual Camera" gets picture and nothing else. Sound has to travel
            as a second, separate device.

            This adds a PipeWire loopback with a sink on one end and a virtual
            source on the other: OBS monitors into the sink, and the source
            appears to every other program as an ordinary microphone. A plain
            null sink would work too, but only for programs willing to select a
            monitor as their input, which many are not
          ''
          // {default = true;};

        sinkName = mkOption {
          type = str;
          default = "OBS Virtual Audio";
          description = "What OBS sends to — its Monitoring Device.";
        };

        sourceName = mkOption {
          type = str;
          default = "OBS Virtual Microphone";
          description = "What everything else sees as a microphone.";
        };
      };
    };

    config = {
      programs.obs-studio = {
        enable = true;
        inherit (cfg) plugins;
        package = mkIf cfg.cudaSupport (pkgs.obs-studio.override {cudaSupport = true;});
      };
      cosmos.system.impermanence.persist.directories = [".config/obs-studio"];

      # Read by the user's own pipewire daemon, which is the one OBS talks to.
      # `.conf` here is SPA JSON, of which plain JSON is a subset.
      #
      # Two settings in OBS finish the job, and neither can be set from here:
      # the config in ~/.config/obs-studio is OBS's to rewrite, and it is
      # persisted rather than generated. In Settings → Audio → Advanced, set
      # Monitoring Device to the sink below; then, per source, Advanced Audio
      # Properties → Audio Monitoring → "Monitor and Output".
      xdg.configFile."pipewire/pipewire.conf.d/50-obs-virtual-audio.conf" =
        mkIf cfg.virtualAudio.enable
        {
          text = builtins.toJSON {
            "context.modules" = [
              {
                name = "libpipewire-module-loopback";
                args = {
                  "node.description" = cfg.virtualAudio.sourceName;
                  # The sink half. OBS's monitoring output lands here.
                  "capture.props" = {
                    "node.name" = "obs_virtual_audio";
                    "node.description" = cfg.virtualAudio.sinkName;
                    "media.class" = "Audio/Sink";
                    "audio.position" = ["FL" "FR"];
                  };
                  # The source half, and the reason for the loopback rather
                  # than a bare null sink: Audio/Source/Virtual is listed as a
                  # microphone, where a sink's monitor is listed as a monitor
                  # and hidden by anything that filters those out.
                  "playback.props" = {
                    "node.name" = "obs_virtual_mic";
                    "node.description" = cfg.virtualAudio.sourceName;
                    "media.class" = "Audio/Source/Virtual";
                    "audio.position" = ["FL" "FR"];
                  };
                };
              }
            ];
          };
        };
    };
  };
}
