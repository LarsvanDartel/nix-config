# home.keyring — gnome-keyring Secret Service (proton apps depend on it).
{...}: {
  den.aspects.home.keyring.homeManager = {pkgs, ...}: {
    services.gnome-keyring.enable = true;
    # The default `ssh` component collides with programs.ssh.startAgent.
    services.gnome-keyring.components = ["pkcs11" "secrets"];
    cosmos.system.impermanence.persist.directories = [".local/share/keyrings"];

    # u2f login never unlocks the keyring: blank its passphrase in seahorse (accepted: the disk is LUKS).
    # The prompter needs desktop.greetd's `services.gnome.gnome-keyring`.
    home.packages = [pkgs.seahorse];
  };
}
