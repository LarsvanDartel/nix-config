{inputs, ...}: {
  flake-file.inputs.stylix = {
    url = "github:nix-community/stylix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.nixos.desktop = {
    config,
    lib,
    ...
  }: let
    inherit (lib.modules) mkDefault;
  in {
    imports = [inputs.stylix.nixosModules.stylix];

    config = {
      stylix = {
        enable = true;
        base16Scheme = mkDefault config.home-manager.users.${config.cosmos.user.name}.stylix.base16Scheme;
        homeManagerIntegration = {
          followSystem = false;
          autoImport = true;
        };
      };
    };
  };
}
