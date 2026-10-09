# core.home-manager — shared home-manager NixOS-module config.
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
