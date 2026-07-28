# home.proton.* — Proton apps. The keyring-backed ones include home.keyring.
{den, ...}: let
  keyring = den.aspects.home.keyring;
in {
  # Proton Mail Bridge (local IMAP/SMTP for a normal mail client).
  den.aspects.home.proton.mail-bridge = {
    includes = [keyring];
    homeManager = {...}: {
      services.protonmail-bridge.enable = true;
      cosmos.system.impermanence.persist.directories = [
        ".config/protonmail"
        ".local/share/protonmail"
      ];
    };
  };

  # Proton Mail desktop app.
  den.aspects.home.proton.mail-desktop.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.protonmail-desktop];
    cosmos.system.impermanence.persist.directories = [".config/Proton Mail"];
  };

  # Proton Pass desktop app.
  den.aspects.home.proton.pass.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.proton-pass];
    cosmos.system.impermanence.persist.directories = [".config/Proton Pass"];
  };

  # Proton Pass CLI.
  den.aspects.home.proton.pass-cli = {
    includes = [keyring];
    homeManager = {pkgs, ...}: {
      home.packages = [pkgs.proton-pass-cli];
      cosmos.system.impermanence.persist.directories = [".config/proton-pass"];
    };
  };

  # Proton VPN GUI.
  den.aspects.home.proton.vpn = {
    includes = [keyring];
    homeManager = {pkgs, ...}: {
      home.packages = [pkgs.proton-vpn];
      cosmos.system.impermanence.persist.directories = [".config/Proton"];
    };
  };

  # Proton VPN CLI.
  den.aspects.home.proton.vpn-cli = {
    includes = [keyring];
    homeManager = {pkgs, ...}: {
      home.packages = [pkgs.proton-vpn-cli];
      cosmos.system.impermanence.persist.directories = [".config/Proton"];
    };
  };
}
