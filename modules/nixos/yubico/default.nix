{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.yubico;
in {
  options.modules.yubico = {
    enable = lib.mkEnableOption "yubico";
  };

  config = lib.mkIf cfg.enable {
    services.udev.packages = [pkgs.yubikey-personalization];
    services.udev.extraRules = ''
      ACTION=="remove",\
        ENV{ID_BUS}=="usb",\
        ENV{ID_MODEL_ID}=="0407",\
        ENV{ID_VENDOR_ID}=="1050",\
        ENV{ID_VENDOR}=="Yubico",\
        RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
    '';

    security.pam.services = {
      login.u2fAuth = true;
      sudo.u2fAuth = true;
    };

    security.pam.yubico = {
      enable = true;
      mode = "challenge-response";
      id = ["29617754" "32433838"];
    };

    security.pam.u2f = {
      enable = true;
      settings = {
        cue = true;
        interactive = true;
      };
    };
  };
}
