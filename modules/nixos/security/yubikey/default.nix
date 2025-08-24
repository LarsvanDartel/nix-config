{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.security.yubikey;
in {
  options.security.yubikey = {
    enable = mkEnableOption "yubikey";
  };

  config = mkIf cfg.enable {
    services = {
      pcscd.enable = true;
      udev.packages = with pkgs; [yubikey-personalization];
      dbus.packages = [pkgs.gcr];

      # INFO: lock PC on yubikey removal
      udev.extraRules = ''
        ACTION=="remove",\
         ENV{ID_BUS}=="usb",\
         ENV{ID_MODEL_ID}=="0407",\
         ENV{ID_VENDOR_ID}=="1050",\
         ENV{ID_VENDOR}=="Yubico",\
         RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
      '';
    };

    security.pam.services = {
      swaylock = {
        u2fAuth = true;
      };

      hyprlock = {
        u2fAuth = true;
      };

      login = {
        u2fAuth = true;
      };

      sudo = {
        u2fAuth = true;
      };
    };
  };
}
