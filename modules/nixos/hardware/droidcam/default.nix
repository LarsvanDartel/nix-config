{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.hardware.droidcam;
in {
  options.cosmos.hardware.droidcam = {
    enable = mkEnableOption "droidcam (use an Android/iOS phone as a webcam)";
  };

  config = mkIf cfg.enable {
    # DroidCam feeds the phone's video into a v4l2loopback virtual camera and its
    # audio into an ALSA loopback device, so other apps (browsers, OBS, etc.) see
    # a regular webcam/mic. The DroidCam client always grabs the first available
    # loopback (video0 is the built-in camera, so it takes video1) unless run
    # with -dev=PATH, so claim video1 here to keep its label correct.
    cosmos.hardware.v4l2loopback.devices = [
      {
        number = 1;
        label = "DroidCam";
      }
    ];
    boot.kernelModules = ["snd-aloop"];

    environment.systemPackages = [pkgs.droidcam];

    cosmos.user.extraGroups = ["video"];
  };
}
