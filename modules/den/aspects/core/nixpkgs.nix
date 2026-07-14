# core.nixpkgs aspect — carries our overlays + allowUnfree onto den-produced
# hosts (and their home-manager, which uses per-user nixpkgs under den).
# Reuses the flake-parts `config.nixpkgs.overlays` aggregator (local packages
# from modules/pkgs/*) and adds the stable/unstable/nur base overlays, matching
# modules/meta/nixpkgs.nix. Every host includes this via the default role.
{
  inputs,
  config,
  ...
}: let
  stable = final: _prev: {
    stable = import inputs.nixpkgs-stable {
      inherit (final) system;
      config.allowUnfree = true;
    };
  };

  unstable = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final) system;
      config.allowUnfree = true;
    };
  };

  overlays =
    config.nixpkgs.overlays
    ++ [
      stable
      unstable
      inputs.nur.overlays.default
    ];

  nixpkgs = {
    config.allowUnfree = true;
    inherit overlays;
  };
in {
  den.aspects.core.nixpkgs = {
    nixos = {inherit nixpkgs;};
    homeManager = {inherit nixpkgs;};
  };
}
