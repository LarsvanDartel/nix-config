# The `nixos` server user (autologin, wheel). Account created by den batteries;
# password/keys come from core.sops / core.ssh (which read cosmos.user.name).
{den, ...}: {
  den.aspects.nixos = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "zsh")
    ];
  };
}
