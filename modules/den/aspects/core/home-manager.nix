# core.home-manager — HM NixOS-module config. den auto-imports the HM module
# for users with the homeManager class; this sets shared options.
# useGlobalPkgs=true so home shares the OS pkgs (overlays via core.nixpkgs).
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
