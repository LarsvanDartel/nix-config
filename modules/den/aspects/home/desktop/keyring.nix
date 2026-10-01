# home.keyring — gnome-keyring Secret Service (proton apps depend on it).
{...}: {
  den.aspects.home.keyring.homeManager = {pkgs, ...}: {
    services.gnome-keyring.enable = true;
    # Default component set includes `ssh`, whose agent collides with
    # core.ssh's `programs.ssh.startAgent` (both fight over SSH_AUTH_SOCK).
    # We only want the secret-service + pkcs11 pieces here.
    services.gnome-keyring.components = ["pkcs11" "secrets"];
    cosmos.system.impermanence.persist.directories = [".local/share/keyrings"];

    # fprintd/pam_u2f sit `sufficient` ahead of pam_unix in the `login` PAM
    # stack (see desktop.greetd), so biometric login short-circuits before a
    # password is typed and pam_gnome_keyring has nothing to unlock with.
    # seahorse is here to blank the login keyring's passphrase (Login keyring
    # → Change Password → blank) so the session module unlocks it on every
    # login path; voyager's disk is LUKS-encrypted at rest, so this is not a
    # blank check. Needs desktop.greetd's `services.gnome.gnome-keyring`
    # (registers gcr's prompter on the session bus) or seahorse's own
    # unlock/change-password dialog has nothing to render through.
    home.packages = [pkgs.seahorse];
  };
}
