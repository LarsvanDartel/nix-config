# services.tangled — a self-hosted Tangled knot: git repositories addressed by
# ATProto identity rather than by an account on someone else's forge.
#
# A knot is the part that actually holds the code. Identity, issues and pull
# requests live as ATProto records; the knot serves git over HTTP and SSH and
# answers to a DID. That is the whole reason this is worth running: the repos
# are on the array here, and the social layer is data rather than a database in
# a company.
#
# Two halves reach this host, and they arrive very differently:
#
#   HTTP   :5555, over the mesh, published by gaia's netbird-proxy like every
#          other service.
#   SSH    port 22 on gaia, forwarded at L4 to *:2222 here — deliberately not
#          :22. NetBird's agent redirects <mesh-ip>:22 to its own embedded SSH
#          server (core/ssh.nix documents this at length), so a forward to :22
#          would reach that instead of OpenSSH and every git push would fail
#          with a host key warning and "Permission denied (password)".
#
# The knot does not run an SSH daemon of its own. It appends a `Match User git`
# block with an AuthorizedKeysCommand to the system sshd, which is why nothing
# here touches ports or authentication: root key auth, deploy-rs and :2222 are
# all untouched. One consequence worth knowing — anything that later adds to
# `services.openssh.extraConfig` lands *inside* that Match block, because
# nixpkgs appends extraConfig to the end of sshd_config.
{
  den,
  inputs,
  ...
}: {
  flake-file.inputs.tangled.url = "git+https://tangled.org/tangled.org/core";

  den.aspects.services.tangled = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.tangled;
    in {
      imports = [inputs.tangled.nixosModules.knot];

      options.cosmos.services.tangled = {
        owner = mkOption {
          type = str;
          example = "did:plc:xxxxxxxxxxxxxxxxxxxxxxxx";
          description = ''
            The DID that owns this knot, from the Tangled settings page.

            No default on purpose: a knot registered to the wrong identity looks
            like it works right up until it refuses every push, so this should
            fail the build rather than guess.
          '';
        };

        hostname = mkOption {
          type = str;
          default = "knot.lvdar.nl";
          description = ''
            Public name. Covered by the existing *.lvdar.nl wildcard in
            services/acme.nix, so it needs no certificate work — and it must
            match what gaia publishes, since the knot signs its registration
            with this name.
          '';
        };

        port = mkOption {
          type = port;
          default = 5555;
          description = "HTTP listener, reached over the mesh by netbird-proxy.";
        };

        stateDir = mkOption {
          type = str;
          default = "/tank/git";
          description = ''
            Repositories and the knot's SQLite database.

            On the array rather than the module's /home/git default: these are
            the canonical copy of the code, and the 250 GB system SSD already
            carries every other service's state. Being on /tank also means
            sanoid snapshots cover them.

            Deliberately NOT added to cosmos.system.impermanence.persist — /tank
            is a ZFS pool outside the persist layer, and an entry there would
            bind-mount /persist over the top and silently move the repositories
            back onto the SSD. hosts/endeavour.nix documents that trap twice.
          '';
        };
      };

      config = {
        sops.secrets."keys/tangled/knot-env" = {};

        # The module points the git user's home at stateDir and creates it, but
        # the parent has to exist on the pool first — same shape as loki.nix.
        systemd.tmpfiles.rules = [
          "d ${cfg.stateDir} 0755 git git - -"
        ];

        services.tangled.knot = {
          enable = true;
          inherit (cfg) stateDir;

          server = {
            owner = cfg.owner;
            hostname = cfg.hostname;
            listenAddr = "0.0.0.0:${toString cfg.port}";
          };

          # KNOT_SERVER_SECRET lives here rather than in the store.
          environmentFile = config.sops.secrets."keys/tangled/knot-env".path;

          # sshd already opens 22 and 2222 for the whole fleet, and the mesh
          # exposure below is what actually matters. Letting this module also
          # manage the firewall would just add a second owner of the same rule.
          openFirewall = false;
        };

        # Reachable from gaia over WireGuard, and from nowhere else.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
