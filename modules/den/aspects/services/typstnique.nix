# typstnique service.
{inputs, ...}: {
  flake-file.inputs.typstnique.url = "github:LarsvanDartel/typstnique";

  den.aspects.services.typstnique.nixos = {...}: {
    imports = [inputs.typstnique.nixosModules.default];

    cosmos.system.impermanence.persist.directories = ["/var/lib/typstnique"];

    services.typstnique = {
      enable = true;
      port = 3030;
    };
  };
}
