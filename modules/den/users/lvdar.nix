# lvdar — the primary user's own home config.
{...}: {
  den.aspects.lvdar = {
    homeManager = {osConfig, ...}: {
      # Host-only identities (voyager's iDRAC key) belong in den.aspects.<host>.provides.lvdar.
      cosmos.cli.programs.ssh.identities = [osConfig.networking.hostName];
    };
  };
}
