# User gnome-keyring daemon providing a Secret Service. Proton Mail Bridge,
# Proton VPN and pass-cli store credentials here. Imported by the proton
# features that need it. For auto-unlock at login the host also needs PAM
# integration (e.g. security.pam.services.greetd.enableGnomeKeyring = true).
{...}: {
  flake.modules.homeManager.keyring = {...}: {
    services.gnome-keyring.enable = true;

    cosmos.system.impermanence.persist.directories = [".local/share/keyrings"];
  };
}
