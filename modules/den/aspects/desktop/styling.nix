# desktop.styling — system stylix. base16Scheme set directly to Nord (the old
# config read it from the home user's stylix; setting it directly avoids a
# home→nixos cross-eval and matches the scheme home uses).
{inputs, ...}: {
  den.aspects.desktop.styling.nixos = {pkgs, ...}: {
    imports = [inputs.stylix.nixosModules.stylix];

    stylix = {
      enable = true;
      base16Scheme = "${pkgs.base16-schemes}/share/themes/nord.yaml";
      homeManagerIntegration = {
        followSystem = false;
        autoImport = true;
      };
    };
  };
}
