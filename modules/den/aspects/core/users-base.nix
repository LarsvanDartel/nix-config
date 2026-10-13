# core.users-base — system-wide user policy + the cosmos.user.extraGroups
# collector. cosmos.user.name comes from the host's den user entity.
{lib, ...}: {
  den.aspects.core.users-base = {
    includes = [
      ({host, ...}: let
        users = lib.attrValues host.users;
      in
        assert lib.assertMsg (lib.length users == 1)
        "core.users-base: host ${host.name} must declare exactly one user (cosmos.user.name is singular), has ${toString (lib.length users)}"; {
          name = "users-base/user-name@${host.name}";
          nixos.cosmos.user.name = (lib.head users).userName;
        })
    ];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) listOf str;
    in {
      options.cosmos.user.extraGroups = mkOption {
        type = listOf str;
        default = [];
        description = "Extra groups for the primary user (accumulated by features).";
      };

      config = {
        users.mutableUsers = false;
        users.users.${config.cosmos.user.name}.extraGroups = config.cosmos.user.extraGroups;
      };
    };
  };
}
