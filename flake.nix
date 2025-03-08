{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    lib = nixpkgs.lib;
    mkConfig = hosts:
      lib.attrsets.concatMapAttrs (hostName: config: {
        ${hostName} = lib.nixosSystem {
          specialArgs = {inherit inputs system;};
          modules = [
            config.host
            ./modules/nixos
            {
              home-manager.extraSpecialArgs = {inherit inputs system;};
              host.users = config.users;
              networking.hostName = lib.mkDefault hostName;
            }
            inputs.disko.nixosModules.default
            inputs.impermanence.nixosModules.impermanence
            inputs.home-manager.nixosModules.home-manager
            inputs.stylix.nixosModules.stylix
          ];
        };
      })
      hosts;
  in {
    formatter.${system} = pkgs.alejandra;

    nixosConfigurations = mkConfig {
      "S20212041" = {
        host = ./hosts/laptop/configuration.nix;
        users."lvdar" = {
          sudo = true;
          config = ./users/lvdar.nix;
        };
      };
    };

    homeManagerModules.default = ./modules/home-manager;
  };
}
