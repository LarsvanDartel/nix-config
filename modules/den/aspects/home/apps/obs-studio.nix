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

    # A sink that goes nowhere, so its monitor is a recording of whatever was
    # played into it. Created by a client on purpose — see the unit below.
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
      cudaSupport = mkOption {
        type = bool;
        default = false;
        description = "Build OBS with NVENC support (from-source rebuild).";
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
        package = mkIf cfg.cudaSupport (pkgs.obs-studio.override {cudaSupport = true;});
      };
      cosmos.system.impermanence.persist.directories = [".config/obs-studio"];

      # A pipewire client, not a pipewire.conf.d context.modules entry: an
      # earlier attempt (libpipewire-module-loopback, media.class
      # Audio/Source/Virtual) segfaulted pipewire 1.6.8 ("can't add port:
      # -28") and took the daemon down in a restart loop — no sound at all.
      # As a separate process the worst case is no virtual device.
      #
      # Hence a sink monitor rather than a virtual source: Audio/Source/Virtual
      # is the class that crashes, and monitors are listed everywhere
      # microphones are.
      #
      # Two OBS-side settings finish this and can't be set from here (its
      # config is persisted and OBS rewrites it): Settings → Audio → Advanced
      # → Monitoring Device = this sink, and per source, Advanced Audio
      # Properties → Audio Monitoring → "Monitor and Output".
      systemd.user.services.obs-virtual-audio = mkIf cfg.virtualAudio.enable {
        Unit = {
          Description = "Virtual audio sink to accompany OBS's virtual camera";
          # The node lives only as long as this client; nothing owns it
          # outside pipewire's lifetime.
          After = ["pipewire.service"];
          BindsTo = ["pipewire.service"];
        };
        Service = {
          ExecStart = "${createSink}";
          Restart = "on-failure";
          RestartSec = 2;
        };
        # Wanted by pipewire, not at login, so it follows daemon restarts.
        Install.WantedBy = ["pipewire.service"];
      };
    };
  };
}
