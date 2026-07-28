# home.libreoffice
{...}: {
  den.aspects.home.libreoffice.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/libreoffice/"];
    home.packages = with pkgs; [
      libreoffice-qt
      hunspell
      hunspellDicts.uk_UA
      hunspellDicts.th_TH
    ];
  };
}
