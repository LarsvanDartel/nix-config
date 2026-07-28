# home.proton.pass — Proton Pass desktop app.
{...}: {
  den.aspects.home.proton.pass.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.proton-pass];
    cosmos.system.impermanence.persist.directories = [".config/Proton Pass"];
  };
}
