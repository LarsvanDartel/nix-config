# home.proton.vpn-cli — Proton VPN CLI (keyring-backed).
{den, ...}: {
  den.aspects.home.proton.vpn-cli = {
    includes = [den.aspects.home.keyring];
    homeManager = {pkgs, ...}: {
      home.packages = [pkgs.proton-vpn-cli];
      cosmos.system.impermanence.persist.directories = [".config/Proton"];
    };
  };
}
