# deploy-rs: remote deployment of the hosts with magic rollback. Nodes are
# derived from den's `flake.nixosConfigurations`. Deploy a host with:
#   nix run github:serokell/deploy-rs .#<host>
{
  inputs,
  config,
  lib,
  ...
}: let
  # Where each host actually answers. The bare config name resolves nowhere, so
  # every host needs an entry or deploy-rs tries the name as a hostname.
  #
  # The mesh supplies the rest: peers are addressable by name from anywhere, so
  # a roaming voyager deploys to endeavour exactly as it does from the LAN, with
  # no per-network addresses to keep straight. That is the whole point of the
  # migration, and this is where it shows.
  #
  # gaia stays on its public name deliberately. It runs the control plane, so
  # if the mesh is what needs fixing, the mesh is not how to reach it.
  #
  # `--hostname <ip>` overrides any of these when a host is off the mesh.
  addresses = {
    gaia = "lvdar.nl";
    endeavour = "endeavour.${dnsDomain}";
    voyager = "voyager.${dnsDomain}";
    pioneer = "pioneer.${dnsDomain}";
  };

  # Matches cosmos.services.netbird.dnsDomain. Not read from a host config:
  # this is flake-level, and reaching into a nixosConfiguration from here to
  # pull one string would make every deploy evaluate a host to find its address.
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

      # Not :22. NetBird's agent redirects the mesh address's :22 to its own
      # embedded SSH server, which authenticates through NetBird rather than by
      # key — so a deploy to <host>.nb.lvdar.nl:22 is refused as
      # "Permission denied (password)". core.ssh gives OpenSSH :2222 as well
      # for exactly this, and using it everywhere keeps gaia (reached by its
      # public name, where the redirect does not apply) on the same rule.
      sshOpts = ["-p" "2222"];

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
