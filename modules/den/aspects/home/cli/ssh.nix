# home.ssh
{
  cosmosLib,
  den,
  lib,
  ...
}: let
  inherit (cosmosLib) get-file-names get-flake-path get-file-name-without-extension;

  keys-path = get-flake-path "modules/den/aspects/core/_ssh-keys";
  # Only id_*.pub are identities; yubikey-*.pub and authorized.nix sit beside them.
  available-identities = map (name: builtins.replaceStrings ["id_" ".pub"] ["" ""] name) (lib.filter (lib.hasPrefix "id_") (get-file-names keys-path));

  servers = lib.filter (h: h.server) (lib.attrValues (lib.mergeAttrsList (lib.attrValues den.hosts)));
  # One Host block below serves every server, so they must share an account.
  serverUsers = lib.unique (map (h: (lib.head (lib.attrValues h.users)).userName) servers);
  serverUser =
    lib.throwIfNot (lib.length serverUsers == 1)
    "home.ssh: servers have different accounts (${toString serverUsers}); split the Host block"
    (lib.head serverUsers);
in {
  den.aspects.home.ssh.homeManager = {
    config,
    osConfig,
    lib,
    ...
  }: let
    inherit (lib.attrsets) mergeAttrsList;
    inherit (lib.strings) optionalString;
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf enum;
    inherit (lib.hm.dag) entryBefore;

    cfg = config.cosmos.cli.programs.ssh;

    # The host's own file (hosts/<host>), decrypted here with the user age key.
    private-key-file = osConfig.sops.defaultSopsFile;
    keys = map (name: keys-path + "/id_${name}.pub") cfg.identities;

    ssh-file = key: ".ssh/${get-file-name-without-extension key}";
    ssh-dir = "${optionalString config.cosmos.system.impermanence.active "/persist"}${config.cosmos.user.home}/.ssh";
  in {
    options.cosmos.cli.programs.ssh = {
      identities = mkOption {
        type = listOf (enum available-identities);
        default = [];
      };
    };

    config = {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        # Servers' account (else a misleading "Permission denied
        # (publickey)"). Must precede the catch-all (ssh keeps the first value).
        # Port 2222: sshd's only port, NetBird owns :22 on mesh addresses. See core/ssh.nix.
        settings."*.nb.lvdar.nl" = entryBefore ["*"] {
          User = serverUser;
          Port = 2222;
        };

        # Only the qualified name resolves.
        settings.${lib.concatMapStringsSep " " (h: h.name) servers} = entryBefore ["*"] {
          HostName = "%h.nb.lvdar.nl";
          User = serverUser;
          Port = 2222;
        };

        settings."*" = {
          addKeysToAgent = "yes";
          forwardAgent = false;
          compression = false;
          serverAliveInterval = 0;
          serverAliveCountMax = 3;
          hashKnownHosts = false;
          userKnownHostsFile = "${ssh-dir}/known_hosts";
          controlMaster = "no";
          controlPath = "${ssh-dir}/master-%r@%n:%p";
          controlPersist = "no";
          identitiesOnly = true;
          identityFile = map (key: "~/${ssh-file key}") keys;
          UpdateHostKeys = "no";
        };
      };

      home.file =
        mergeAttrsList (
          map (key: {
            "${ssh-file key}.pub".source = key;
          })
          keys
        )
        // lib.optionalAttrs (lib.elem osConfig.networking.hostName cfg.identities) {
          # Default paths for tools that don't read IdentityFile; every device key is ed25519.
          ".ssh/id_ed25519.pub".source = keys-path + "/id_${osConfig.networking.hostName}.pub";
          ".ssh/id_ed25519".source = config.lib.file.mkOutOfStoreSymlink config.sops.secrets."keys/ssh/${osConfig.networking.hostName}".path;
        };

      sops.secrets = mergeAttrsList (
        map (name: {
          "keys/ssh/${name}" = {
            sopsFile = private-key-file;
            path = "${config.home.homeDirectory}/${ssh-file "id_${name}"}";
          };
        })
        cfg.identities
      );
    };
  };
}
