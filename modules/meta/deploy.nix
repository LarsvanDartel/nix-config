# deploy-rs: remote deployment of the hosts with magic rollback. Nodes are
# derived from den's `flake.nixosConfigurations`. Deploy a host with:
#   nix run github:serokell/deploy-rs .#<host>
{
  inputs,
  config,
  lib,
  ...
}: let
  # Every host needs an entry — the bare config name resolves nowhere. Mesh
  # peers are addressable by name from anywhere; gaia is the exception, on
  # its public name deliberately: it runs the control plane, so the mesh is
  # not how to reach it when the mesh is what needs fixing. `--hostname <ip>`
  # overrides any of these when a host is off the mesh.
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

      # Not :22 — NetBird redirects the mesh address's :22 to its own SSH
      # server (key-less, "Permission denied (password)"). OpenSSH answers
      # on :2222 (core.ssh); used for gaia too so one rule covers all hosts.
      sshOpts = ["-p" "2222"];

      profiles.system = {
        user = "root";
        # deploy-rs would use the local username, which only exists on
        # voyager; core.ssh permits root with the same keys (root skips sudo).
        sshUser = "root";
        magicRollback = true;
        # Build here and push the closure: remoteBuild on the Pi means a
        # 4x A53 / 1 GB compiling the uncached rpi kernel — about a day, and
        # it OOMs.
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
