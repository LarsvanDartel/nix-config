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
      den.aspects.roles.home-base
    ];

    homeManager = {osConfig, ...}: {
      # The default is just this host's own key, which is ed25519 — and the
      # iDRAC runs OpenSSH 6.6 and offers only ssh-rsa, ssh-dss and
      # ecdsa-sha2-nistp256, so it cannot parse one. Hence a second, RSA
      # identity used for that one destination.
      #
      # Named for what it is for rather than for a host, unlike the others:
      # every existing key identifies a machine, this identifies a purpose.
      cosmos.cli.programs.ssh.identities = [osConfig.networking.hostName "idrac"];
    };
  };
}
