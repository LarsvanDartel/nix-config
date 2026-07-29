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
        # Everything is built here and the closure pushed. The aarch64 Pi is
        # emulated via voyager's binfmt (boot.binfmt.emulatedSystems): slow, but
        # the alternative — `remoteBuild` on a Pi 3 — means a 4x A53 with 1 GB of
        # RAM compiling nixos-hardware's linux-rpi kernel, which is not in
        # cache.nixos.org. That takes the better part of a day and tends to OOM.
        remoteBuild = false;
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
