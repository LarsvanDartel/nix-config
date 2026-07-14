{config, ...}: let
  inherit (config.flake.modules.homeManager) keyring;
in {
  # Proton VPN (GUI). Connects through NetworkManager, so the host needs the
  # networkmanager feature with the wireguard/openvpn plugins. Proton VPN 4.x
  # stores its account/session in a Secret Service keyring and its settings
  # under ~/.config/Proton/VPN.
  flake.modules.homeManager.proton-vpn = {pkgs, ...}: {
    imports = [keyring];

    home.packages = [pkgs.proton-vpn];

    cosmos.system.impermanence.persist.directories = [".config/Proton"];
  };

  # Proton VPN CLI (`protonvpn`). Same NetworkManager requirement as the GUI.
  flake.modules.homeManager.proton-vpn-cli = {pkgs, ...}: {
    imports = [keyring];

    home.packages = [pkgs.proton-vpn-cli];

    cosmos.system.impermanence.persist.directories = [".config/Proton"];
  };
}
