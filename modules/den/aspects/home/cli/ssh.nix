# home.ssh
{cosmosLib, ...}: let
  inherit (cosmosLib) get-file-names get-flake-path get-file-name-without-extension;

  keys-path = get-flake-path "modules/den/aspects/core/_ssh-keys";
  available-identities = map (name: builtins.replaceStrings ["id_" ".pub"] ["" ""] name) (get-file-names keys-path);
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

    private-key-file = "${config.cosmos.security.sops.sopsFolder}/common/secrets.yaml";
    keys = map (name: keys-path + "/id_${name}.pub") cfg.identities;

    ssh-file = key: ".ssh/${get-file-name-without-extension key}";
    ssh-dir = "${optionalString config.cosmos.system.impermanence.active "/persist"}${config.cosmos.user.home}/.ssh";
  in {
    options.cosmos.cli.programs.ssh = {
      identities = mkOption {
        type = listOf (enum available-identities);
        default = [osConfig.networking.hostName];
      };
    };

    config = {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        # Servers' account is `nixos` (else a misleading "Permission denied
        # (publickey)"); a literal because den can't read another host's
        # cosmos.user.name. Must precede the catch-all (ssh keeps the first value).
        # Port 2222: NetBird hijacks :22 on mesh addresses. See core/ssh.nix.
        settings."*.nb.lvdar.nl" = entryBefore ["*"] {
          User = "nixos";
          Port = 2222;
        };

        # Only the qualified name resolves.
        settings."endeavour gaia pioneer" = entryBefore ["*"] {
          HostName = "%h.nb.lvdar.nl";
          User = "nixos";
          Port = 2222;
        };

        settings."*" = {
          addKeysToAgent = "yes";
          forwardAgent = true;
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

      home.file = mergeAttrsList (
        map (key: {
          "${ssh-file key}.pub".source = key;
        })
        keys
      );

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
