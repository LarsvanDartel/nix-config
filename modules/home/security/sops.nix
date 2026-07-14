{inputs, ...}: {
  flake.modules.homeManager.common = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str;
  in {
    imports = [
      inputs.sops-nix.homeManagerModules.sops
    ];

    options.cosmos.security.sops = {
      sopsFolder = mkOption {
        type = str;
        default = builtins.toString inputs.nix-secrets + "/users";
      };
    };

    config = {
      sops = {
        # NOTE: This is the host-specific age-key file and is supposed to be generated
        # beforehand and populated by the nixos sops feature from the secrets repository
        age.keyFile = "/home/${config.home.username}/.config/sops/age/keys.txt";

        defaultSopsFile = "${config.cosmos.security.sops.sopsFolder}/${config.home.username}.yaml";
        validateSopsFiles = false;
      };
    };
  };
}
