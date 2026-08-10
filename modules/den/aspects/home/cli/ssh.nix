# home.ssh (was the ssh contribution to homeManager.common).
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

        # The servers' primary account is `nixos`, not `lvdar` — only voyager
        # names its user after its owner. ssh defaults to the *local* username,
        # so `ssh endeavour.nb.lvdar.nl` from voyager asks for an account that
        # does not exist there and is refused with a bare "Permission denied
        # (publickey)", which reads like a key problem rather than a name one.
        #
        # A literal, because den cannot read another host's `cosmos.user.name`
        # any more than it can read its ports.
        #
        # `settings` is a DAG, and ssh takes the first value it is given for a
        # keyword, so these have to be ordered ahead of the catch-all below.
        settings."*.nb.lvdar.nl" = entryBefore ["*"] {
          User = "nixos";
        };

        # So the short name works too: the qualified one is all that resolves.
        settings."endeavour gaia pioneer" = entryBefore ["*"] {
          HostName = "%h.nb.lvdar.nl";
          User = "nixos";
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
