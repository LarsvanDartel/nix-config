{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.security.keyring;
in {
  options.cosmos.security.keyring = {
    enable = mkEnableOption ''
      a user gnome-keyring daemon providing a Secret Service. Apps like Proton
      Mail Bridge, Proton VPN and pass-cli store their credentials here. For the
      keyring to auto-unlock at login (so those apps start without prompting),
      the host also needs PAM integration, e.g.
      `security.pam.services.greetd.enableGnomeKeyring = true`
    '';
  };

  config = mkIf cfg.enable {
    services.gnome-keyring.enable = true;

    cosmos.system.impermanence.persist.directories = [".local/share/keyrings"];
  };
}
