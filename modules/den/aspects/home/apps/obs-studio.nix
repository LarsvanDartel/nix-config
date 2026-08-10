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

    # A sink that goes nowhere, whose monitor is therefore a recording of
    # whatever was played into it. Created by a client rather than declared in
    # pipewire.conf.d on purpose — see the unit below.
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

      # Deliberately a client of pipewire rather than a `context.modules` entry
      # in pipewire.conf.d, which is how these are usually written.
      #
      # Loaded into the daemon, anything that goes wrong here goes wrong to all
      # audio: an earlier attempt at this used libpipewire-module-loopback with
      # a `media.class = Audio/Source/Virtual` playback node, which on pipewire
      # 1.6.8 fails to create its ports ("can't add port: -28") and then
      # segfaults cleaning them up. Because the module lived in the daemon, the
      # daemon died with it, in a restart loop, and the machine came up with no
      # sound at all. As a separate process the worst case is no virtual
      # device.
      #
      # It is also why the microphone is this sink's monitor rather than a
      # virtual source of its own: Audio/Source/Virtual is the class that would
      # be listed directly as a microphone, and it is the class that crashes.
      # A monitor is listed by everything that offers monitors — which, having
      # checked, includes what this is for.
      #
      # Two OBS-side settings finish the job and neither can be set from here:
      # its config is persisted rather than generated, and OBS rewrites it. In
      # Settings → Audio → Advanced set Monitoring Device to this sink, then
      # per source, Advanced Audio Properties → Audio Monitoring → "Monitor and
      # Output".
      systemd.user.services.obs-virtual-audio = mkIf cfg.virtualAudio.enable {
        Unit = {
          Description = "Virtual audio sink to accompany OBS's virtual camera";
          # The node lives as long as this client, and there is nothing to own
          # it before pipewire exists or after it goes away.
          After = ["pipewire.service"];
          BindsTo = ["pipewire.service"];
        };
        Service = {
          ExecStart = "${createSink}";
          Restart = "on-failure";
          RestartSec = 2;
        };
        # Started by pipewire rather than at login, so it follows a restart of
        # the daemon instead of being left behind by one.
        Install.WantedBy = ["pipewire.service"];
      };
    };
  };
}
