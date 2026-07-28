# home.proton.pass-cli — Proton Pass CLI (keyring-backed).
{den, ...}: {
  den.aspects.home.proton.pass-cli = {
    includes = [den.aspects.home.keyring];
    homeManager = {pkgs, ...}: {
      home.packages = [pkgs.proton-pass-cli];
      cosmos.system.impermanence.persist.directories = [".config/proton-pass"];
    };
  };
}
