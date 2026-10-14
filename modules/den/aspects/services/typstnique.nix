# typstnique service.
{inputs, ...}: let
  # services.typstnique.port and the netbird-service target.
  port = 3030;
in {
  flake-file.inputs.typstnique.url = "github:LarsvanDartel/typstnique";

  den.aspects.services.typstnique.netbird-service = {host, ...}: {
    typstnique = {
      bearerAuth.enable = false;
      targets = [
        {
          peer = host.name;
          inherit port;
        }
      ];
    };
  };

  den.aspects.services.typstnique.nixos = {...}: {
    imports = [inputs.typstnique.nixosModules.default];

    cosmos.system.impermanence.persist.directories = ["/var/lib/typstnique"];
    cosmos.services.netbird.client.exposedPorts = [port];

    services.typstnique = {
      enable = true;
      inherit port;
      # 0.0.0.0: edgeTerminated, traffic arrives from gaia's netbird-proxy.
      address = "0.0.0.0";
    };
  };
}
