{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkOption;
  inherit (lib.types) listOf submodule int str bool;
  inherit (lib.modules) mkIf;
  inherit (lib.lists) sort length;
  inherit (lib.strings) concatMapStringsSep;

  cfg = config.cosmos.hardware.v4l2loopback;

  # Sort by device number so /dev/videoN assignment is stable regardless of the
  # order in which consumers (OBS, DroidCam, ...) register their devices.
  devices = sort (a: b: a.number < b.number) cfg.devices;
  field = f: concatMapStringsSep "," f devices;
in {
  options.cosmos.hardware.v4l2loopback = {
    devices = mkOption {
      default = [];
      description = ''
        Virtual V4L2 loopback cameras to create. Each entry becomes a
        /dev/videoN device that applications (OBS's virtual camera, DroidCam,
        browsers) can write to or read from. All requested devices are loaded
        from a single merged modprobe config at boot, so multiple consumers can
        register devices without their `options v4l2loopback` lines colliding.
      '';
      example = lib.literalExpression ''[{number = 1; label = "OBS Virtual Camera";}]'';
      type = listOf (submodule {
        options = {
          number = mkOption {
            type = int;
            description = "Device node number (/dev/videoN). Keep clear of real cameras (usually video0).";
          };
          label = mkOption {
            type = str;
            description = "Card label shown to applications.";
          };
          exclusiveCaps = mkOption {
            type = bool;
            default = true;
            description = ''
              Announce either capture or output capabilities exclusively (not
              both). Required for Chromium-based apps (browsers, Zoom) to detect
              the device as a camera.
            '';
          };
        };
      });
    };
  };

  config = mkIf (cfg.devices != []) {
    boot.kernelModules = ["v4l2loopback"];
    boot.extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
    # card_label is a comma-separated array, but modprobe only strips one outer
    # pair of quotes from a value. Quoting each label (card_label="a","b") would
    # leave the inner quotes literal, so v4l2loopback would see them as part of
    # the names. Quote the whole comma-joined list once instead, which preserves
    # spaces in labels and still splits cleanly on the commas.
    boot.extraModprobeConfig = ''
      options v4l2loopback devices=${toString (length devices)} video_nr=${field (d: toString d.number)} card_label="${field (d: d.label)}" exclusive_caps=${field (d:
        if d.exclusiveCaps
        then "1"
        else "0")}
    '';

    # OBS needs polkit to start its virtual camera.
    security.polkit.enable = true;
  };
}
