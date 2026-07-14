# DO-NOT-EDIT. This file was auto-generated using github:vic/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  description = "lvdar's NixOS config";

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

  nixConfig = {
    abort-on-warn = true;
  };

  inputs = {
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-file.url = "github:denful/flake-file";
    flake-parts.url = "github:hercules-ci/flake-parts";
    hm-wrapper-modules = {
      url = "github:sini/hm-wrapper-modules";
      inputs = {
        home-manager.follows = "home-manager";
        nix-wrapper-modules.follows = "nix-wrapper-modules";
        nixpkgs.follows = "nixpkgs";
      };
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    import-tree.url = "github:vic/import-tree";
    jellarr.url = "github:venkyr77/jellarr";
    make-shell.url = "github:nicknovitski/make-shell";
    nix-secrets.url = "git+ssh://git@github.com/LarsvanDartel/nix-secrets.git?shallow=1";
    nix-wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules/f318ea7274683aa1af36cff22f7b40420807324a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    oisd-big-unbound = {
      url = "https://big.oisd.nl/unbound";
      flake = false;
    };
    oisd-nsfw-unbound = {
      url = "https://nsfw.oisd.nl/unbound";
      flake = false;
    };
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    typstnique.url = "github:LarsvanDartel/typstnique";
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
  };
}
