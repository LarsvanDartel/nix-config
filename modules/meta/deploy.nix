# deploy-rs: remote deployment of the hosts with magic rollback. Nodes are
# derived from the `configurations` option (see configurations.nix). Deploy a
# host with:  nix run github:serokell/deploy-rs .#<host>
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
    lib.mapAttrs (name: c: {
      hostname = name;
      profiles.system = {
        user = "root";
        magicRollback = true;
        # Cross-building the aarch64 Pi from an x86 host is impractical; build it
        # on the target instead.
        remoteBuild = c.system == "aarch64-linux";
        path =
          inputs.deploy-rs.lib.${c.system}.activate.nixos
          config.flake.nixosConfigurations.${name};
      };
    })
    config.configurations;

  # deploy-rs's own validity checks, folded into `nix flake check`.
  flake.checks =
    lib.mapAttrs
    (system: deployLib: deployLib.deployChecks config.flake.deploy)
    inputs.deploy-rs.lib;
}
