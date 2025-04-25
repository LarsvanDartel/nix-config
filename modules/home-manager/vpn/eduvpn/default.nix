{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.vpn.eduvpn;
in {
  options.modules.vpn.eduvpn = {
    enable = mkEnableOption "eduvpn";
  };

  config = mkIf cfg.enable {
    modules.persist.directories = [".config/eduvpn"];
    home.packages = with pkgs; [
      eduvpn-client
    ];
    xdg.desktopEntries.eduvpn = {
      name = "EduVPN";
      comment = "EduVPN client";
      icon = "${pkgs.eduvpn-client}/lib/python3.12/site-packages/eduvpn/data/share/icons/hicolor/128x128/apps/org.eduvpn.client.png";
      exec = "${pkgs.eduvpn-client}/bin/eduvpn-gui";
      terminal = false;
      categories = ["Network"];
    };
  };
}
