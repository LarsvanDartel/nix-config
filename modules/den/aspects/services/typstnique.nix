# typstnique service.
{inputs, ...}: {
  flake-file.inputs.typstnique.url = "github:LarsvanDartel/typstnique";

  den.aspects.services.typstnique.nixos = {...}: {
    imports = [inputs.typstnique.nixosModules.default];

    cosmos.system.impermanence.persist.directories = ["/var/lib/typstnique"];

    services.typstnique = {
      enable = true;
      port = 3030;
      # netbird-proxy reaches this over the mesh, as it does every other
      # published service — even though it happens to run on the same host, so
      # the request leaves and re-enters through WireGuard. Uniformity is worth
      # that: the vhost, certificate and CrowdSec check are the ones every
      # other service gets, rather than a second, hand-written path.
      #
      # The firewall is what limits reach: 3030 is opened on the netbird
      # interface alone (netbird.client.exposedPorts in hosts/gaia.nix).
      address = "0.0.0.0";
    };
  };
}
