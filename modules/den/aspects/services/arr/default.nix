# The *arr stack base aspect: the `media` group and the directories the rest
# hang off. Per-service files beside this one include `services.arr`;
# arr/vpn.nix adds the VPN-confinement namespace for the download clients.
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
      # Every service in the family runs as its own user in this group, which
      # is what lets them hand files to one another under mediaDir.
      users.groups.media = {};
      cosmos.user.extraGroups = ["media"];
      systemd.tmpfiles.rules = ["d '${cfg.mediaDir}'  0775 root media - -"];
    };
  };
}
