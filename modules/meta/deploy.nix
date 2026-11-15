# deploy-rs: how the servers are deployed, by hand from voyager, with magic
# rollback. Nodes are derived from den's host entities (address and system
# are entity data, so listing nodes does not evaluate any host); voyager is
# not one, it switches itself with `nh os switch`. From the dev shell:
#   deploy                           # servers with deployByDefault, from a committed tree
#   deploy .#<host>                  # one, including pioneer
#   deploy .                         # every server
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
        # The 240 s / 30 s defaults rolled back a good pioneer deploy
        # (2026-11-15): its activation on the SD card outlasted them, and the
        # rollback left it running the new system under the old profile. They
        # only bound how long a hung activation takes to be noticed.
        activationTimeout = 1200;
        confirmTimeout = 120;
        # Building the uncached rpi kernel on the Pi takes ~a day and OOMs.
        remoteBuild = false;
        path = inputs.deploy-rs.lib.${host.system}.activate.nixos config.flake.nixosConfigurations.${name};
      };
    })
    servers;

  # deploy-rs runs `nix flake check` before every deploy, and deploy-activate
  # builds every node's closure: with pioneer's, that is a long wait even for
  # `deploy .#gaia`. Checked with what a bare `deploy` covers; pioneer still
  # gets its build when it is deployed.
  flake.checks =
    lib.mapAttrs
    (system: deployLib:
      deployLib.deployChecks (config.flake.deploy
        // {nodes = lib.filterAttrs (name: _: servers.${name}.deployByDefault) config.flake.deploy.nodes;}))
    inputs.deploy-rs.lib;

  # `deploy` in the dev shell: deploy-rs from the lock, not `nix run
  # github:serokell/deploy-rs` (the nodes' `activate` is built from this input
  # and must match the CLI). Without a flake argument it deploys only the
  # deployByDefault servers; deploy-rs itself has no notion of a default set.
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
