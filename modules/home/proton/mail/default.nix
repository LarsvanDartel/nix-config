{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkMerge;

  cfg = config.cosmos.proton.mail;
in {
  options.cosmos.proton.mail = {
    bridge.enable = mkEnableOption ''
      Proton Mail Bridge. Runs the bridge as a user service exposing Proton over
      local IMAP (127.0.0.1:1143) and SMTP (127.0.0.1:1025) so a normal mail
      client (see cosmos.mail.thunderbird) can talk to it. The first login is
      interactive: run `protonmail-bridge --cli` once, `login`, then read the
      account's IMAP/SMTP password with `info`
    '';

    desktop.enable = mkEnableOption "Proton Mail desktop app (standalone client, no bridge needed)";
  };

  config = mkMerge [
    (mkIf cfg.bridge.enable {
      # Starts `protonmail-bridge --noninteractive` as a systemd user service. It
      # reads your Proton session from the keyring rather than prompting, so it
      # only works after the interactive login above.
      services.protonmail-bridge.enable = true;

      # The bridge keeps your Proton credentials in a Secret Service keyring;
      # without one it can't start noninteractively.
      cosmos.security.keyring.enable = true;

      cosmos.system.impermanence.persist.directories = [
        ".config/protonmail" # bridge config + encrypted vault
        ".local/share/protonmail" # bridge IMAP cache (gluon)
      ];
    })

    (mkIf cfg.desktop.enable {
      home.packages = [pkgs.protonmail-desktop];

      cosmos.system.impermanence.persist.directories = [".config/Proton Mail"];
    })
  ];
}
