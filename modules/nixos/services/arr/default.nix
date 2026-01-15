{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) path;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.arr;
in {
  options.cosmos.services.arr = {
    enable = mkEnableOption "arr stack";

    mediaDir = mkOption {
      type = path;
      default = "/data/media";
      description = ''
        The location of the media directory for the services.
      '';
    };

    stateDir = mkOption {
      type = path;
      default = "/data/.state/arr";
      description = ''
        The location of the state directory for the services.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.groups.media = {};
    cosmos.user.extraGroups = ["media"];

    systemd.tmpfiles.rules = [
      "d '${cfg.mediaDir}'  0775 root media - -"
    ];
  };
}
