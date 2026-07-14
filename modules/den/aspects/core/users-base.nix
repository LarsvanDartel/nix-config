# core.users-base — system-wide user policy that isn't per-user (was part of
# modules/nixos/user.nix). Per-user records come from the define-user battery.
{...}: {
  den.aspects.core.users-base.nixos = {...}: {
    users.mutableUsers = false;
  };
}
