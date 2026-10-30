# services.remote-builder — endeavour builds (and emulates aarch64) over ssh-ng on the mesh for every host that includes .client.
#
# Clients arrive on the `nix-builder-client` quirk ({address, key} from host facts). Payloads must stay
# `{host, ...}:`; a `{config, ...}:` payload would make endeavour evaluate each client's configuration.
{den, ...}: let
  inherit (den.lib.policy) pipe;
  builder = den.hosts.x86_64-linux.endeavour;
in {
  den.quirks.nix-builder-client.description = "Hosts allowed to build on the remote builder ({address, key}: mesh IP and SSH host key)";

  # collect, not collectAll: every client is x86_64.
  # den reads these argument names (host scope, host-entity filter), so
  # deadnix must not strip them as unused.
  # deadnix: skip
  den.policies.nix-builder-client = {host, ...}: [
    (pipe.from "nix-builder-client" [
      (pipe.collect (
        # deadnix: skip
        {host, ...}: true
      ))
    ])
  ];

  den.aspects.services.remote-builder = {
    includes = [den.policies.nix-builder-client];

    nixos = {nix-builder-client, ...}: {
      assertions =
        map (c: {
          assertion = c.address != null && c.key != null;
          message = "services.remote-builder: a nix-builder-client host lacks meshAddress or sshHostKey (den.hosts facts)";
        })
        nix-builder-client;

      nix.sshServe = {
        enable = true;
        protocol = "ssh-ng";
        # ssh-ng builders must be trusted, i.e. root-equivalent on this daemon.
        trusted = true;
        # from=: :2222 is also reachable through gaia's public DNAT.
        keys = map (c: ''from="${c.address}" ${c.key}'') nix-builder-client;
      };

      boot.binfmt.emulatedSystems = ["aarch64-linux"];
    };
  };

  den.aspects.services.remote-builder.client = {
    nix-builder-client = {host, ...}: {
      address = host.meshAddress;
      key = host.sshHostKey;
    };

    nixos = {
      config,
      lib,
      ...
    }: {
      nix = {
        distributedBuilds = true;
        settings.builders-use-substitutes = true;
        buildMachines = [
          {
            hostName = builder.meshAddress;
            protocol = "ssh-ng";
            sshUser = "nix-ssh";
            # The host key doubles as the client identity: root-only, persisted, no new secret.
            sshKey = (lib.head config.services.openssh.hostKeys).path;
            systems = ["x86_64-linux" "aarch64-linux"];
            supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
            maxJobs = 8;
            speedFactor = 4;
          }
        ];
      };

      # NetBird owns mesh :22; the daemon's ssh reads only system config.
      programs.ssh.extraConfig = ''
        Host ${builder.meshAddress}
          Port 2222
          ConnectTimeout 5
          IdentitiesOnly yes
      '';
    };
  };
}
