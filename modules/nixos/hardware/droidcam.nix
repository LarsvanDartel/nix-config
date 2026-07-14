# DroidCam depends on the v4l2loopback feature (it registers a loopback camera),
# so importing droidcam pulls v4l2loopback in with it.
{config, ...}: let
  inherit (config.flake.modules.nixos) v4l2loopback;
in {
  flake.modules.nixos.droidcam = {pkgs, ...}: {
    imports = [v4l2loopback];

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
