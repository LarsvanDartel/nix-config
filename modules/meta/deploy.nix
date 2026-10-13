# deploy-rs: remote deployment of the hosts with magic rollback. Nodes are
# derived from den's host entities (address and system are entity data, so
# listing nodes does not evaluate any host). Deploy a host with:
#   nix run github:serokell/deploy-rs .#<host>
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
    lib.mapAttrs (name: host: {
      hostname = host.deployAddress;

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
        path = inputs.deploy-rs.lib.${host.system}.activate.nixos config.flake.nixosConfigurations.${name};
      };
    })
    (lib.mergeAttrsList (lib.attrValues config.den.hosts));

  flake.checks =
    lib.mapAttrs
    (system: deployLib: deployLib.deployChecks config.flake.deploy)
    inputs.deploy-rs.lib;
}
