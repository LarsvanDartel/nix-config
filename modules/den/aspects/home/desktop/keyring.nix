# home.keyring — gnome-keyring Secret Service (proton apps depend on it).
{...}: {
  den.aspects.home.keyring.homeManager = {pkgs, ...}: {
    services.gnome-keyring.enable = true;
    # The default `ssh` component collides with programs.ssh.startAgent.
    services.gnome-keyring.components = ["pkcs11" "secrets"];
    cosmos.system.impermanence.persist.directories = [".local/share/keyrings"];

    # Biometric login skips pam_gnome_keyring's password, so blank the login
    # keyring's passphrase in seahorse (voyager's disk is LUKS-encrypted).
    # Needs desktop.greetd's `services.gnome.gnome-keyring` for the prompter.
    home.packages = [pkgs.seahorse];
  };
}
