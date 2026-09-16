# typstnique service.
{inputs, ...}: {
  flake-file.inputs.typstnique.url = "github:LarsvanDartel/typstnique";

  den.aspects.services.typstnique.nixos = {...}: {
    imports = [inputs.typstnique.nixosModules.default];

    cosmos.system.impermanence.persist.directories = ["/var/lib/typstnique"];

    services.typstnique = {
      enable = true;
      port = 3030;
      # 0.0.0.0, not loopback: endeavour is edgeTerminated, connections arrive
      # from gaia's netbird-proxy over WireGuard. The firewall limits reach
      # (netbird.client.exposedPorts in hosts/endeavour.nix).
      address = "0.0.0.0";
    };
  };
}
