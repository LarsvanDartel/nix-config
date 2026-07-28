# home.proton.mail-desktop — Proton Mail desktop app.
{...}: {
  den.aspects.home.proton.mail-desktop.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.protonmail-desktop];
    cosmos.system.impermanence.persist.directories = [".config/Proton Mail"];
  };
}
