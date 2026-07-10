{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkMerge;

  cfg = config.cosmos.proton.vpn;
in {
  options.cosmos.proton.vpn = {
    gui.enable = mkEnableOption ''
      Proton VPN (GUI). Connects through NetworkManager, so the host needs
      `networking.networkmanager.enable` with the wireguard/openvpn plugins
    '';

    cli.enable = mkEnableOption ''
      Proton VPN CLI (`protonvpn`). Same NetworkManager requirement as the GUI
    '';
  };

  config = mkMerge [
    (mkIf cfg.gui.enable {
      home.packages = [pkgs.proton-vpn];
    })

    (mkIf cfg.cli.enable {
      home.packages = [pkgs.proton-vpn-cli];
    })

    (mkIf (cfg.gui.enable || cfg.cli.enable) {
      # Proton VPN 4.x stores its account/session in a Secret Service keyring
      # and its settings under ~/.config/Proton/VPN.
      cosmos.security.keyring.enable = true;

      cosmos.system.impermanence.persist.directories = [".config/Proton"];
    })
  ];
}
