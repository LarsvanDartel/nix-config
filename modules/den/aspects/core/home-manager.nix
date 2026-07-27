# core.home-manager — home-manager NixOS-module config (was in
# modules/nixos/profiles/common.nix). den's home-manager support auto-imports
# the HM module for users with the homeManager class; this sets shared options.
# useGlobalPkgs=true so home shares the OS pkgs (which already carry our overlays
# via core.nixpkgs), matching the pre-migration behaviour.
{inputs, ...}: {
  den.aspects.core.home-manager.nixos = {...}: {
    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "bak";
      extraSpecialArgs = {inherit inputs;};
      sharedModules = [
        ({osConfig, ...}: {home.stateVersion = osConfig.system.stateVersion;})
      ];
    };
  };
}
