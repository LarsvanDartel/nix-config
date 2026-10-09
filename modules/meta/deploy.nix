# deploy-rs: remote deployment of the hosts with magic rollback. Nodes are
# derived from den's `flake.nixosConfigurations`. Deploy a host with:
#   nix run github:serokell/deploy-rs .#<host>
{
  inputs,
  config,
  lib,
  ...
}: let
  # gaia uses its public name deliberately: it runs the mesh control plane,
  # so it must be reachable when the mesh is broken.
  addresses = {
    gaia = "lvdar.nl";
    endeavour = "endeavour.${dnsDomain}";
    voyager = "voyager.${dnsDomain}";
    pioneer = "pioneer.${dnsDomain}";
  };

  # Matches cosmos.services.netbird.dnsDomain — hand-synced: reading it from
  # a nixosConfiguration here would evaluate a host on every deploy.
  dnsDomain = "nb.lvdar.nl";
in {
  flake-file.inputs.deploy-rs = {
    url = "github:serokell/deploy-rs";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.deploy.nodes =
    lib.mapAttrs (name: nixos: let
      system = nixos.config.nixpkgs.hostPlatform.system;
    in {
      hostname = addresses.${name} or name;

      # Not :22 — NetBird redirects the mesh address's :22 to its own
      # key-less SSH server; OpenSSH listens on :2222 (core.ssh).
      sshOpts = ["-p" "2222"];

      profiles.system = {
        user = "root";
        # The local username only exists on voyager; core.ssh permits root.
        sshUser = "root";
        magicRollback = true;
        # Building the uncached rpi kernel on the Pi takes ~a day and OOMs.
        remoteBuild = false;
        path = inputs.deploy-rs.lib.${system}.activate.nixos nixos;
      };
    })
    config.flake.nixosConfigurations;

  flake.checks =
    lib.mapAttrs
    (system: deployLib: deployLib.deployChecks config.flake.deploy)
    inputs.deploy-rs.lib;
}
