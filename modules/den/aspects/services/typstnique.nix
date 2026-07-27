# typstnique service (was flake.modules.nixos.typstnique). Input declared by the
# legacy module during migration; referenced here.
{inputs, ...}: {
  den.aspects.services.typstnique.nixos = {...}: {
    imports = [inputs.typstnique.nixosModules.default];

    cosmos.system.impermanence.persist.directories = ["/var/lib/typstnique"];

    services.typstnique = {
      enable = true;
      port = 3030;
    };
  };
}
