# deploy-rs: remote deployment of the hosts with magic rollback. Nodes are
# derived from den's `flake.nixosConfigurations`. Deploy a host with:
#   nix run github:serokell/deploy-rs .#<host>
{
  inputs,
  config,
  lib,
  ...
}: let
  # Where each host actually answers. The bare config name is not usable: no
  # resolver knows these names yet — which is the whole reason for the NetBird
  # migration, and it bites hardest here, since deploying the control plane is
  # what makes the names work in the first place.
  #
  # Once the mesh is up these become <host>.nb.lvdar.nl and this map can go.
  addresses = {
    gaia = "lvdar.nl";
  };
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
      profiles.system = {
        user = "root";
        # Without this deploy-rs uses the *local* username, which only exists on
        # voyager — every other host's primary user is `nixos`. core.ssh permits
        # root login and gives root the same authorized keys, so connecting as
        # root is both simplest and avoids needing sudo to activate.
        sshUser = "root";
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
