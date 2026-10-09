# The primary user `lvdar`, built from den batteries (define-user,
# primary-user, user-shell).
{den, ...}: {
  den.aspects.lvdar = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "zsh")
      den.aspects.roles.home-base
    ];

    homeManager = {
      osConfig,
      lib,
      ...
    }: {
      # iDRAC's OpenSSH 6.6 can't parse ed25519 — hence an RSA identity.
      # 2048 bits: iDRAC 7/8 rejects 4096-bit keys (Dell KB 000142481).
      cosmos.cli.programs.ssh.identities = [osConfig.networking.hostName "idrac"];

      # A jump through pioneer: the BMC's sshd must only be reachable from
      # the host in front of it.
      programs.ssh.settings."idrac" = lib.hm.dag.entryBefore ["*"] {
        HostName = "192.168.2.111";
        ProxyJump = "pioneer";

        # No User: the BMC account shares the local username.
        IdentityFile = "~/.ssh/id_idrac";
        IdentitiesOnly = true;

        # BMC OpenSSH 6.6 can only sign SHA-1 ssh-rsa.
        PubkeyAcceptedAlgorithms = "+ssh-rsa";
        HostKeyAlgorithms = "+ssh-rsa";

        # Silences only the permanent post-quantum warning; blanket `no` would
        # hide future weak-crypto warnings too.
        WarnWeakCrypto = "no-pq-kex";

        # Two slow handshake hops per command; re-enable multiplexing here
        # (disabled globally).
        ControlMaster = "auto";
        ControlPersist = "10m";
      };
    };
  };
}
