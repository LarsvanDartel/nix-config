# core.nixpkgs — overlays + allowUnfree for den-produced hosts (and their
# home-manager, which shares the OS pkgs via useGlobalPkgs). Overlays come
# from inputs only — reading the flake-parts `config` here would create a
# flake→host→flake recursion. Local packages (modules/pkgs/*) arrive via
# self.overlays.default once a host needs them (voyager).
{inputs, ...}: let
  stable = final: _prev: {
    stable = import inputs.nixpkgs-stable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  };

  unstable = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  };

  overlays = [
    stable
    unstable
    inputs.nur.overlays.default
    inputs.self.overlays.default
  ];

  nixpkgs = {
    config.allowUnfree = true;
    inherit overlays;
  };
in {
  den.aspects.core.nixpkgs.nixos = {inherit nixpkgs;};
}
