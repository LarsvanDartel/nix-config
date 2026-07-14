{config, ...}: let
  inherit (config.flake.modules.homeManager) keyring;
in {
  # Proton Mail Bridge. Runs the bridge as a user service exposing Proton over
  # local IMAP (127.0.0.1:1143) and SMTP (127.0.0.1:1025) so a normal mail
  # client (see the thunderbird feature) can talk to it. First login is
  # interactive: `protonmail-bridge --cli`, `login`, then `info`.
  flake.modules.homeManager.proton-mail-bridge = {...}: {
    imports = [keyring];

    services.protonmail-bridge.enable = true;

    cosmos.system.impermanence.persist.directories = [
      ".config/protonmail" # bridge config + encrypted vault
      ".local/share/protonmail" # bridge IMAP cache (gluon)
    ];
  };

  # Proton Mail desktop app (standalone client, no bridge needed).
  flake.modules.homeManager.proton-mail-desktop = {pkgs, ...}: {
    home.packages = [pkgs.protonmail-desktop];

    cosmos.system.impermanence.persist.directories = [".config/Proton Mail"];
  };
}
