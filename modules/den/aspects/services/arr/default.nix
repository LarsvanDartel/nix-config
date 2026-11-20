# services.arr — *arr stack base: the `media` group and the directories the other services hang off.
{...}: {
  den.aspects.services.arr.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) path;

    cfg = config.cosmos.services.arr;
  in {
    options.cosmos.services.arr = {
      mediaDir = mkOption {
        type = path;
        default = "/data/media";
      };
      stateDir = mkOption {
        type = path;
        default = "/data/.state/arr";
      };
    };

    config = {
      users.groups.media = {};
      cosmos.user.extraGroups = ["media"];
      systemd.tmpfiles.rules = ["d '${cfg.mediaDir}'  0775 root media - -"];
    };
  };
}
