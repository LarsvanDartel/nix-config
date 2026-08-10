# The *arr stack. This file holds only the base aspect: the `media` group and
# the two directories everything else hangs off. Each service is its own file
# beside this one and includes `services.arr` for them; `arr/vpn.nix` adds the
# VPN-confinement namespace that the download clients run inside.
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
