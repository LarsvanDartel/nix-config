# home.proton.vpn — Proton VPN GUI (keyring-backed).
{den, ...}: {
  den.aspects.home.proton.vpn = {
    includes = [den.aspects.home.keyring];
    homeManager = {pkgs, ...}: {
      home.packages = [pkgs.proton-vpn];
      cosmos.system.impermanence.persist.directories = [".config/Proton"];
    };
  };
}
