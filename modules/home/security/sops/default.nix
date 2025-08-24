{
  config,
  lib,
  inputs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  sopsFolder = builtins.toString inputs.nix-secrets + "/users";

  cfg = config.security.sops;
in {
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  options.security.sops = {
    enable = mkEnableOption "sops";
  };

  config = mkIf cfg.enable {
    sops = {
      # NOTE: This is the host-specific age-key file and is supposed to be generated
      # beforehand and populated by modules/nixos/security/sops/default.nix from the
      # secrets repository
      age.keyFile = "/home/${config.rainbow.user.name}/.config/sops/age/keys.txt";

      defaultSopsFile = "${sopsFolder}/${config.rainbow.user.name}.yaml";
      validateSopsFiles = false;

      secrets = {
        # placeholder
      };
    };
  };
}
