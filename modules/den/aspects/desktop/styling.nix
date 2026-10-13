# desktop.styling — system stylix + every user's home.styling (to-users). The
# scheme is one plain binding shared by both sides, not read from the home
# user's stylix (that would be a home→nixos cross-eval).
{
  den,
  inputs,
  ...
}: let
  scheme = "nord";
  darkMode = true;
in {
  flake-file.inputs.stylix = {
    url = "github:nix-community/stylix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.styling = {
    provides.to-users = {
      includes = [den.aspects.home.styling];
      homeManager.cosmos.desktops.common.styling.theme.${scheme} = {
        enable = true;
        inherit darkMode;
      };
    };

    nixos = {
      lib,
      pkgs,
      ...
    }: {
      imports = [inputs.stylix.nixosModules.stylix];

      stylix = {
        enable = true;
        # The home theme module resolves the same file (light = "-light" suffix).
        base16Scheme = "${pkgs.base16-schemes}/share/themes/${scheme}${lib.optionalString (!darkMode) "-light"}.yaml";
        homeManagerIntegration = {
          followSystem = false;
          autoImport = true;
        };
      };
    };
  };
}
