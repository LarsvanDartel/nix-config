# home.obs-studio — OBS Studio with plugins and a virtual audio sink for the virtual camera
{...}: {
  den.aspects.home.obs-studio.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) listOf package str;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.programs.obs-studio;

    createSink = pkgs.writeShellScript "obs-virtual-audio" ''
      exec ${pkgs.pipewire}/bin/pw-cli -m create-node adapter '{
        factory.name = support.null-audio-sink
        node.name = "obs_virtual_audio"
        node.description = "${cfg.virtualAudio.name}"
        media.class = "Audio/Sink"
        audio.position = [ FL FR ]
        monitor.channel-volumes = true
      }'
    '';
  in {
    options.cosmos.programs.obs-studio = {
      plugins = mkOption {
        type = listOf package;
        default = [];
        description = "OBS Studio plugins to install.";
      };

      virtualAudio = {
        enable =
          mkEnableOption ''
            a virtual audio device to pair with the virtual camera.

            The virtual camera is v4l2loopback and V4L2 carries no audio — the
            kernel API has no notion of it — so anything picking up "OBS
            Virtual Camera" gets picture and silence. Sound has to arrive as a
            separate device, and this is it: OBS monitors into the sink, and
            its monitor is what other programs record from
          ''
          // {default = true;};

        name = mkOption {
          type = str;
          default = "OBS Virtual Audio";
          description = ''
            Shown as a sink in OBS's Monitoring Device list, and as
            "Monitor of <name>" wherever a microphone is chosen.
          '';
        };
      };
    };

    config = {
      programs.obs-studio = {
        enable = true;
        inherit (cfg) plugins;
      };
      cosmos.system.impermanence.persist.directories = [".config/obs-studio"];

      # A sink monitor, not a loopback Audio/Source/Virtual: that crash-loops pipewire.
      # Set in OBS by hand: Monitoring Device = this sink; per source "Monitor and Output".
      systemd.user.services.obs-virtual-audio = mkIf cfg.virtualAudio.enable {
        Unit = {
          Description = "Virtual audio sink to accompany OBS's virtual camera";
          After = ["pipewire.service"];
          BindsTo = ["pipewire.service"];
        };
        Service = {
          ExecStart = "${createSink}";
          Restart = "on-failure";
          RestartSec = 2;
        };
        # Wanted by pipewire, so it follows daemon restarts.
        Install.WantedBy = ["pipewire.service"];
      };
    };
  };
}
