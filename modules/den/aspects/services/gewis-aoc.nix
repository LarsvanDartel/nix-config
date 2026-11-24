# services.gewisAoc — aoc.lvdar.nl, the live puzzle for the GEWIS Advent of Code talk.
{inputs, ...}: let
  publicPort = 3032;
  # Who solved first. Mesh-only on purpose: opened on the netbird interface, never a netbird-service.
  adminPort = 3033;
in {
  flake-file.inputs.gewis-aoc = {
    url = "git+https://knot.lvdar.nl/did:plc:aomkxcjtprbtc6rzsho5rexe?shallow=1";
    inputs.launchpad.follows = "launchpad";
  };

  den.aspects.services.gewisAoc.netbird-service = {host, ...}: {
    aoc = {
      bearerAuth.enable = false;
      targets = [
        {
          peer = host.name;
          port = publicPort;
        }
      ];
    };
  };

  den.aspects.services.gewisAoc.nixos = {...}: {
    imports = [inputs.gewis-aoc.nixosModules.default];

    cosmos.system.impermanence.persist.directories = ["/var/lib/gewis-aoc"];
    cosmos.services.netbird.client.exposedPorts = [publicPort adminPort];

    services.gewis-aoc = {
      enable = true;
      # 0.0.0.0: edgeTerminated, traffic arrives from gaia's netbird-proxy.
      publicAddress = "0.0.0.0";
      inherit publicPort adminPort;
      # 0.0.0.0, but exposedPorts opens it on the mesh interface only.
      adminAddress = "0.0.0.0";
      leaderboardUrl = "https://gew.is/advent";
    };
  };
}
