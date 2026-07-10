{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.proton.vpn;
in {
  options.cosmos.proton.vpn = {
    enable = mkEnableOption ''
      Proton VPN (GUI). Note the app connects through NetworkManager, so the
      host needs `networking.networkmanager.enable` with the wireguard/openvpn
      plugins; credentials are stored in the keyring
    '';
  };

  config = mkIf cfg.enable {
    home.packages = [pkgs.proton-vpn];

    # Proton VPN 4.x stores its account/session in a Secret Service keyring.
    services.gnome-keyring.enable = true;

    cosmos.system.impermanence.persist.directories = [".config/protonvpn"];
  };
}
