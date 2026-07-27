# core.users-base — system-wide user policy + the cosmos.user.extraGroups
# collector (features append groups; they land on the primary user, merging with
# the wheel/networkmanager the primary-user battery adds). Per-user records come
# from the define-user battery.
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
