{...}: {
  flake.modules.nixos.common = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf str;

    cfg = config.cosmos.networking;
  in {
    options.cosmos.networking = {
      nameservers = mkOption {
        type = listOf str;
        default = ["9.9.9.9"];
        description = "Global DNS nameservers (overridden to loopback by the dnscrypt feature).";
      };
    };

    config = {
      networking = {
        enableIPv6 = true;
        firewall.enable = true;
        # mkDefault so the dnscrypt feature can force loopback resolvers.
        nameservers = lib.mkDefault cfg.nameservers;
      };
    };
  };
}
