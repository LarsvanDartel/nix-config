{
  config,
  lib,
  inputs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) str;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.security.sops;
in {
  imports = [
    inputs.sops-nix.homeManagerModules.sops
  ];

  options.cosmos.security.sops = {
    enable = mkEnableOption "sops";
    sopsFolder = mkOption {
      type = str;
      default = builtins.toString inputs.nix-secrets + "/users";
    };
  };

  config = mkIf cfg.enable {
    sops = {
      # NOTE: This is the host-specific age-key file and is supposed to be generated
      # beforehand and populated by modules/nixos/security/sops/default.nix from the
      # secrets repository
      age.keyFile = "/home/${config.home.username}/.config/sops/age/keys.txt";

      defaultSopsFile = "${cfg.sopsFolder}/${config.home.username}.yaml";
      validateSopsFiles = false;
    };
  };
}
