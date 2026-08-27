# typstnique service.
{inputs, ...}: {
  flake-file.inputs.typstnique.url = "github:LarsvanDartel/typstnique";

  den.aspects.services.typstnique.nixos = {...}: {
    imports = [inputs.typstnique.nixosModules.default];

    cosmos.system.impermanence.persist.directories = ["/var/lib/typstnique"];

    services.typstnique = {
      enable = true;
      port = 3030;
      # Bound to the mesh rather than loopback: this runs on endeavour, which
      # is edgeTerminated, so the connection arrives from gaia's netbird-proxy
      # over WireGuard and a loopback bind would refuse it.
      #
      # The firewall is what limits reach: 3030 is opened on the netbird
      # interface alone (netbird.client.exposedPorts in hosts/endeavour.nix).
      address = "0.0.0.0";
    };
  };
}
