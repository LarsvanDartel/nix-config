# The primary user `lvdar`. Account, shell and home baseline come from
# den.default / den.schema.user (defaults.nix); this is lvdar's own config.
{...}: {
  den.aspects.lvdar = {
    homeManager = {osConfig, ...}: {
      # Each workstation signs and logs in with its own device key; host-only
      # identities (voyager's iDRAC key) come from den.aspects.<host>.provides.lvdar.
      cosmos.cli.programs.ssh.identities = [osConfig.networking.hostName];
    };
  };
}
