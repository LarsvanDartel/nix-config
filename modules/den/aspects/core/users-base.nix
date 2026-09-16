# core.users-base — system-wide user policy + the cosmos.user.extraGroups
# collector (features append groups; they merge with the primary-user
# battery's wheel/networkmanager). Per-user records: define-user battery.
{...}: {
  den.aspects.core.users-base.nixos = {
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
}
