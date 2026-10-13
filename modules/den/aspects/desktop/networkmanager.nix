# desktop.networkmanager
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
        if config.services.resolved.enable
        then "systemd-resolved"
        else if cfg.nameservers == []
        then "default"
        else "none";
    };
  };
}
