{inputs, ...}: let
  additions = final: prev: (prev.lib.packagesFromDirectoryRecursive {
    callPackage = prev.lib.callPackageWith final;
    directory = ../pkgs;
  });

  modifications = final: prev: {
    # example = prev.example.overrideAttrs (previousAttrs: let ... in {
    # ...
    # });
    steam = prev.steam.overrideAttrs {
      package = final.unstable.steam;
    };
    gamemode = prev.gamemode.overrideAttrs {
      package = final.unstable.gamemode;
    };
  };

  stable-packages = final: _: {
    stable = import inputs.nixpkgs-stable {
      inherit (final) system;
      config.allowUnfree = true;
      overlays = [
      ];
    };
  };

  unstable-packages = final: _: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final) system;
      config.allowUnfree = true;
      overlays = [
      ];
    };
  };
in {
  default = final: prev:
    (additions final prev)
    // (modifications final prev)
    // (stable-packages final prev)
    // (unstable-packages final prev);
}
