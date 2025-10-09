{
  config,
  lib,
  ...
}: let
  inherit (lib.custom) get-files get-flake-path get-file-name-without-extension;
  inherit (lib.attrsets) mergeAttrsList;
  inherit (lib.lists) map;
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.ssh;

  keys-path = get-flake-path "modules/nixos/services/ssh/keys";
  keys = get-files keys-path;

  ssh-file = key: ".ssh/${get-file-name-without-extension key}";
in {
  options.cli.programs.ssh = {
    enable = mkEnableOption "ssh";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.files = [".ssh/known_hosts"];

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = {
        "*" = {
          addKeysToAgent = "yes";
          forwardAgent = true;
          identitiesOnly = true;
          identityFile =
            map
            (key: "~/${ssh-file key}")
            keys;
        };
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
