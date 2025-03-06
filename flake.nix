{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";

    # hyprland.url = "git+https://github.com/hyperwm/Hyprland?submodules=1";
    # hyprland.inputs.nixpkgs.follows = "nixpkgs";
    #
    # hyprpanel.url = "github:Jas-SinghFSU/HyprPanel";

    # nixos-hardware.url = "github:nixos/nixos-hardware";
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
    mkConfig = host: users:
      nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs system;};
        modules = [
          host
          ./modules/nixos
          inputs.disko.nixosModules.default
          inputs.impermanence.nixosModules.impermanence
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.extraSpecialArgs = {inherit inputs system;};
            host = {inherit users;};
          }
        ];
      };
  in {
    formatter.${system} = pkgs.alejandra;

    nixosConfigurations = {
      default = mkConfig ./hosts/laptop/configuration.nix {
        "lvdar" = {
          sudo = true;
          config = ./users/lvdar.nix;
        };
      };
    };

    homeManagerModules.default = ./modules/home-manager;
  };
}
