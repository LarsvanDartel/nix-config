# desktop.styling — system stylix. base16Scheme set directly (not read from the
# home user's stylix) to avoid a home→nixos cross-eval; must match home's.
{inputs, ...}: {
  flake-file.inputs.stylix = {
    url = "github:nix-community/stylix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

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
