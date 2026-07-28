# home.proton.mail-bridge — Proton Mail Bridge (local IMAP/SMTP for a mail client).
{den, ...}: {
  den.aspects.home.proton.mail-bridge = {
    includes = [den.aspects.home.keyring];
    homeManager = {...}: {
      services.protonmail-bridge.enable = true;
      cosmos.system.impermanence.persist.directories = [
        ".config/protonmail"
        ".local/share/protonmail"
      ];
    };
  };
}
