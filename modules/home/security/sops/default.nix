{
  config,
  lib,
  inputs,
  ...
}: let
  inherit (lib.attrsets) mergeAttrsList;
  inherit (lib.lists) map;
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  sopsFolder = builtins.toString inputs.nix-secrets + "/users";

  hosts = ["voyager"];

  cfg = config.cosmos.security.sops;
in {
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  options.cosmos.security.sops = {
    enable = mkEnableOption "sops";
  };

  config = mkIf cfg.enable {
    sops = {
      # NOTE: This is the host-specific age-key file and is supposed to be generated
      # beforehand and populated by modules/nixos/security/sops/default.nix from the
      # secrets repository
      age.keyFile = "/home/${config.home.username}/.config/sops/age/keys.txt";

      defaultSopsFile = "${sopsFolder}/${config.home.username}.yaml";
      validateSopsFiles = false;

      secrets =
        {
          # placeholder
        }
        // mergeAttrsList (
          map (name: {
            "keys/ssh/${name}" = {
              sopsFile = "${sopsFolder}/common/secrets.yaml";
              path = "${config.home.homeDirectory}/.ssh/id_${name}";
            };
          })
          hosts
        );
    };
  };
}
