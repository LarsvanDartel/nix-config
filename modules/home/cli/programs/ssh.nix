{cosmosLib, ...}: let
  inherit (cosmosLib) get-file-names get-flake-path get-file-name-without-extension;
in {
  flake.modules.homeManager.common = {
    config,
    osConfig,
    lib,
    ...
  }: let
    inherit (lib.attrsets) mergeAttrsList;
    inherit (lib.strings) optionalString removePrefix removeSuffix;
    inherit (lib.options) mkOption;
    inherit (lib.types) listOf enum;

    cfg = config.cosmos.cli.programs.ssh;

    private-key-file = "${config.cosmos.security.sops.sopsFolder}/common/secrets.yaml";

    keys-path = get-flake-path "modules/nixos/services/ssh/keys";
    available-identities = map (name: removeSuffix ".pub" (removePrefix "id_" name)) (get-file-names keys-path);
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
          identityFile =
            map
            (key: "~/${ssh-file key}")
            keys;
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
