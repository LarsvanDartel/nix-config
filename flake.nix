{
  description = "lvdar's NixOS config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-secrets.url = "git+ssh://git@github.com/LarsvanDartel/nix-secrets.git?shallow=1";

    nixos-hardware.url = "github:nixos/nixos-hardware";

    impermanence.url = "github:nix-community/impermanence";

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvf = {
      url = "github:NotAShelf/nvf/ea3ee477fa1814352b30d114f31bf4895eed053e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    declarative-jellyfin = {
      url = "github:Sveske-Juice/declarative-jellyfin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Minecraft

    modpack-create = {
      url = "github:LarsvanDartel/Modpack-Create/1.21.1-forge";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-minecraft.url = "github:Jan-Bulthuis/nix-minecraft";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    inherit (self) outputs;

    forAllSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
    ];

    lib = nixpkgs.lib.extend (_: _: {cosmos = import ./lib {inherit (nixpkgs) lib;};});
  in {
    # NixOS configurations
    nixosConfigurations = builtins.listToAttrs (
      map (host: {
        name = host;
        value = nixpkgs.lib.nixosSystem {
          specialArgs = {inherit inputs outputs lib;};
          modules =
            [
              ./hosts/${host}
              {
                home-manager = {
                  extraSpecialArgs = {inherit inputs;};
                  sharedModules =
                    [
                      inputs.nur.modules.homeManager.default
                    ]
                    ++ lib.cosmos.get-default-nix-files-recursive ./modules/home;
                };

                networking.hostName = host;
              }
            ]
            ++ (lib.cosmos.get-default-nix-files-recursive ./modules/nixos);
        };
      }) (builtins.attrNames (builtins.readDir ./hosts))
    );

    # Nix formatter available through 'nix fmt' https://github.com/NixOS/nixfmt
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

    # Pre-commit checks
    checks = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        import ./checks.nix {inherit inputs system pkgs;}
    );

    devShells = forAllSystems (
      system:
        import ./shell.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          checks = self.checks.${system};
        }
    );
  };
}
