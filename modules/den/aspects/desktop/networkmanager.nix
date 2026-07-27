# desktop.networkmanager (the networkmanager group is added by the primary-user
# battery, so it is not re-added here).
{...}: {
  den.aspects.desktop.networkmanager.nixos = {
    config,
    pkgs,
    ...
  }: let
    cfg = config.cosmos.networking;
  in {
    cosmos.system.impermanence.persist.directories = ["/etc/NetworkManager"];
    networking.networkmanager = {
      enable = true;
      plugins = [pkgs.networkmanager-openvpn];
      dns =
        if cfg.nameservers == []
        then "default"
        else "none";
    };
  };
}
