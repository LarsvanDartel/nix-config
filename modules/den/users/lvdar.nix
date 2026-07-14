# The primary user `lvdar`. den's batteries replace the hand-rolled user record
# in modules/nixos/user.nix: define-user (the account + HM home dir),
# primary-user (wheel/networkmanager), user-shell (zsh at OS + home).
# Extra groups (video/cdrom/media/…) will arrive via the extraGroups quirk as
# features are converted; the home baseline is added under `homeManager`.
{den, ...}: {
  den.aspects.lvdar = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "zsh")
    ];
  };
}
