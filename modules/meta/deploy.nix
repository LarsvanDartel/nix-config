# deploy — deploy-rs nodes for the servers, deployed by hand from voyager with magic rollback.
{
  inputs,
  config,
  lib,
  ...
}: let
  servers = lib.filterAttrs (_: host: host.server) (lib.mergeAttrsList (lib.attrValues config.den.hosts));
  defaultTargets = lib.concatMapStringsSep " " (name: ".#${name}") (lib.attrNames (lib.filterAttrs (_: host: host.deployByDefault) servers));
in {
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
        # Generous: pioneer's SD-card activation outlasts the 240 s / 30 s defaults, and a rollback
        # then leaves the new system running under the old profile.
        activationTimeout = 1200;
        confirmTimeout = 120;
        # Building the uncached rpi kernel on the Pi takes ~a day and OOMs.
        remoteBuild = false;
        path = inputs.deploy-rs.lib.${host.system}.activate.nixos config.flake.nixosConfigurations.${name};
      };
    })
    servers;

  # Only deployByDefault servers: deploy-rs runs `nix flake check` before every deploy, and
  # pioneer's closure would make even `deploy .#gaia` slow.
  flake.checks =
    lib.mapAttrs
    (system: deployLib:
      deployLib.deployChecks (config.flake.deploy
        // {nodes = lib.filterAttrs (name: _: servers.${name}.deployByDefault) config.flake.deploy.nodes;}))
    inputs.deploy-rs.lib;

  # deploy-rs from the lock, not github:serokell/deploy-rs: the nodes' `activate` comes from this
  # input and must match the CLI. Without a flake argument it deploys only deployByDefault servers.
  perSystem = {
    inputs',
    pkgs,
    ...
  }: {
    make-shells.default.packages = [
      (pkgs.writeShellApplication {
        name = "deploy";
        text = ''
          for arg in "$@"; do
            case "$arg" in
              .* | *"#"*) exec ${lib.getExe' inputs'.deploy-rs.packages.deploy-rs "deploy"} "$@" ;;
            esac
          done
          exec ${lib.getExe' inputs'.deploy-rs.packages.deploy-rs "deploy"} "$@" --targets ${defaultTargets}
        '';
      })
    ];
  };
}
