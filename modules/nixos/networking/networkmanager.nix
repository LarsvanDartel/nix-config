{...}: {
  flake.modules.nixos.desktop = {
    config,
    pkgs,
    ...
  }: let
    cfg = config.cosmos.networking;
  in {
    cosmos.system.impermanence.persist.directories = ["/etc/NetworkManager"];
    cosmos.user.extraGroups = ["networkmanager"];
    networking.networkmanager = {
      enable = true;
      plugins = [pkgs.networkmanager-openvpn];
      # When dnscrypt is imported it forces nameservers to loopback (non-empty),
      # so NetworkManager hands DNS off ("none"); otherwise let NM manage it.
      dns =
        if cfg.nameservers == []
        then "default"
        else "none";
    };
  };
}
