{...}: {
  flake.modules.homeManager.zotero = {pkgs, ...}: {
    home.packages = [pkgs.zotero];

    cosmos.system.impermanence.persist.directories = ["Zotero" ".zotero"];
  };
}
