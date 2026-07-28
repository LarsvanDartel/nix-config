# Feature inputs used by den aspects. Declared here (rather than scattered in the
# old feature files) so removing the legacy skeleton doesn't drop them from the
# generated flake.nix. Core infra inputs (nixpkgs*, home-manager, disko,
# nixos-hardware, nixos-facter, nur) stay in modules/meta/inputs.nix.
{...}: {
  flake-file.inputs = {
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jellarr.url = "github:venkyr77/jellarr";
    typstnique.url = "github:LarsvanDartel/typstnique";
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-secrets.url = "git+ssh://git@github.com/LarsvanDartel/nix-secrets.git?shallow=1";

    oisd-big-unbound = {
      url = "https://big.oisd.nl/unbound";
      flake = false;
    };
    oisd-nsfw-unbound = {
      url = "https://nsfw.oisd.nl/unbound";
      flake = false;
    };
  };
}
