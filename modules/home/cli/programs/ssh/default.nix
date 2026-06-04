{
  config,
  lib,
  ...
}: let
  inherit (lib.cosmos) get-files get-flake-path get-file-name-without-extension;
  inherit (lib.attrsets) mergeAttrsList;
  inherit (lib.lists) map;
  inherit (lib.strings) optionalString;
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.ssh;

  keys-path = get-flake-path "modules/nixos/services/ssh/keys";
  keys = get-files keys-path;

  ssh-file = key: ".ssh/${get-file-name-without-extension key}";
  ssh-dir = "${optionalString config.cosmos.system.impermanence.enable "/persist"}${config.cosmos.user.home}/.ssh";
in {
  options.cosmos.cli.programs.ssh = {
    enable = mkEnableOption "ssh";
  };

  config = mkIf cfg.enable {
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
  };
}
