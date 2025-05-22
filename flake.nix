{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";

    modpack-create.url = "github:LarsvanDartel/Modpack-Create/1.21.1-forge";
    modpack-create.inputs.nixpkgs.follows = "nixpkgs";

    nix-minecraft.url = "github:Jan-Bulthuis/nix-minecraft";

    nvf.url = "github:notashelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs";

    nur.url = "github:nix-community/NUR";
    nur.inputs.nixpkgs.follows = "nixpkgs";

    nix-matlab.url = "gitlab:doronbehar/nix-matlab";
    nix-matlab.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:nixos/nixos-hardware";

    stylix.url = "github:danth/stylix";
    stylix.inputs.home-manager.follows = "home-manager";
  };

  outputs = {nixpkgs, ...} @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    inherit (nixpkgs) lib;
    mkConfig = hosts:
      lib.attrsets.concatMapAttrs (hostName: config: {
        ${hostName} = lib.nixosSystem {
          specialArgs = {inherit inputs system;};
          modules = [
            config.host
            ./modules/nixos
            inputs.disko.nixosModules.default
            inputs.impermanence.nixosModules.impermanence
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = {inherit inputs system;};
                backupFileExtension = "bak";
                sharedModules = [
                  ./modules/home-manager
                  inputs.nvf.homeManagerModules.default
                  inputs.stylix.homeModules.stylix
                  inputs.nur.modules.homeManager.default
                ];
              };
              host.users = config.users;
              networking.hostName = lib.mkDefault hostName;
            }
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
          shell = pkgs.zsh;
          config = ./users/lvdar.nix;
        };
      };
    };
  };
}
