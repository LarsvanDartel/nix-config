# hardware.v4l2loopback — virtual V4L2 loopback cameras (OBS virtual cam, etc).
{...}: {
  den.aspects.hardware.v4l2loopback.nixos = {
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

    devices = sort (a: b: a.number < b.number) cfg.devices;
    field = f: concatMapStringsSep "," f devices;
  in {
    options.cosmos.hardware.v4l2loopback.devices = mkOption {
      default = [];
      description = "Virtual V4L2 loopback cameras to create.";
      type = listOf (submodule {
        options = {
          number = mkOption {
            type = int;
            description = "Device node number (/dev/videoN).";
          };
          label = mkOption {
            type = str;
            description = "Card label shown to applications.";
          };
          exclusiveCaps = mkOption {
            type = bool;
            default = true;
            description = "Announce capture or output capabilities exclusively.";
          };
        };
      });
    };

    config = mkIf (cfg.devices != []) {
      boot.kernelModules = ["v4l2loopback"];
      boot.extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
      boot.extraModprobeConfig = ''
        options v4l2loopback devices=${toString (length devices)} video_nr=${field (d: toString d.number)} card_label="${field (d: d.label)}" exclusive_caps=${field (d:
          if d.exclusiveCaps
          then "1"
          else "0")}
      '';
      security.polkit.enable = true;
    };
  };
}
