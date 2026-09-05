# home.keyring — gnome-keyring Secret Service (proton apps depend on it).
{...}: {
  den.aspects.home.keyring.homeManager = {pkgs, ...}: {
    services.gnome-keyring.enable = true;
    cosmos.system.impermanence.persist.directories = [".local/share/keyrings"];

    # fprintd and pam_u2f are `sufficient` ahead of pam_unix in the `login` PAM
    # stack (see desktop.greetd), so a fingerprint/YubiKey login short-circuits
    # auth before a password is ever typed — pam_gnome_keyring then has nothing
    # to unlock the login keyring with. seahorse is here so the login keyring's
    # passphrase can be blanked out (Login keyring -> Change Password -> blank
    # new password): with an empty passphrase, `pam_gnome_keyring`'s session
    # module unlocks it on any login path, password or biometric. voyager's
    # disk is already LUKS-encrypted at rest, so this trades keyring-specific
    # encryption for a keyring that actually unlocks — not a blank check.
    home.packages = [pkgs.seahorse];
  };
}
