{inputs, ...}: {
  flake-file.inputs.typstnique.url = "github:LarsvanDartel/typstnique";

  flake.modules.nixos.typstnique = {...}: {
    imports = [inputs.typstnique.nixosModules.default];

    cosmos.system.impermanence.persist.directories = ["/var/lib/typstnique"];

    services.typstnique = {
      enable = true;
      port = 3030;
    };
  };
}
