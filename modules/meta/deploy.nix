# deploy-rs: remote deployment of the hosts with magic rollback. Nodes are
# derived from den's `flake.nixosConfigurations`. Deploy a host with:
#   nix run github:serokell/deploy-rs .#<host>
#
# `hostname` defaults to the config name — override per node with a real address
# if it differs from the hostname.
{
  inputs,
  config,
  lib,
  ...
}: {
  flake-file.inputs.deploy-rs = {
    url = "github:serokell/deploy-rs";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.deploy.nodes =
    lib.mapAttrs (name: nixos: let
      system = nixos.config.nixpkgs.hostPlatform.system;
    in {
      hostname = name;
      profiles.system = {
        user = "root";
        magicRollback = true;
        # Cross-building the aarch64 Pi from an x86 host is impractical; build it
        # on the target instead.
        remoteBuild = system == "aarch64-linux";
        path = inputs.deploy-rs.lib.${system}.activate.nixos nixos;
      };
    })
    config.flake.nixosConfigurations;

  # deploy-rs's own validity checks, folded into `nix flake check`.
  flake.checks =
    lib.mapAttrs
    (system: deployLib: deployLib.deployChecks config.flake.deploy)
    inputs.deploy-rs.lib;
}
