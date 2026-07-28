# home.keyring — gnome-keyring Secret Service (proton apps depend on it).
{...}: {
  den.aspects.home.keyring.homeManager = {...}: {
    services.gnome-keyring.enable = true;
    cosmos.system.impermanence.persist.directories = [".local/share/keyrings"];
  };
}
