# core.nixpkgs — overlays + allowUnfree for den-produced hosts. Overlays come
# from inputs only — reading the flake-parts `config` here would create a
# flake→host→flake recursion.
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
