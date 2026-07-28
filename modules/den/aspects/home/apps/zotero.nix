# home.zotero
{...}: {
  den.aspects.home.zotero.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.zotero];
    cosmos.system.impermanence.persist.directories = ["Zotero" ".zotero"];
  };
}
