# core.networking — base networking + the nameservers option (was
# flake.modules.nixos.common in modules/nixos/networking/default.nix).
{...}: {
  den.aspects.core.networking.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool listOf str;

    cfg = config.cosmos.networking;
  in {
    options.cosmos.networking = {
      nameservers = mkOption {
        type = listOf str;
        default = ["9.9.9.9"];
        description = "Global DNS nameservers (overridden to loopback by the dnscrypt feature).";
      };

      edgeTerminated = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether TLS for this host's published services is terminated at the
          network edge rather than here.

          False is the Pangolin arrangement: gaia relays raw TCP and each
          service's `<name>.lvdar.nl` vhost terminates locally with the
          `*.lvdar.nl` wildcard. True is the NetBird one: netbird-proxy
          terminates on gaia and forwards over the mesh to each app's own port,
          so those vhosts are dropped entirely.

          Declared here, in an aspect every host gets through roles.default, so
          the service aspects can read it without depending on nginx or netbird
          being present.

          Only the *public* vhosts are affected. The localhost bridges in
          arr/default.nix are local plumbing into the VPN namespace and are
          unrelated, as is services.acme — kanidm reads the wildcard pem files
          directly for its own listener.
        '';
      };
    };

    config.networking = {
      enableIPv6 = true;
      firewall.enable = true;
      nameservers = lib.mkDefault cfg.nameservers;
    };
  };
}
