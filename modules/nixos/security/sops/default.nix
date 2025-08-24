{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.strings) optionalString;
  inherit (lib.modules) mkIf;

  sopsFolder = builtins.toString inputs.nix-secrets + "/hosts";
  impermanence = config.system.impermanence.enable;

  cfg = config.security.sops;
in {
  imports = [inputs.sops-nix.nixosModules.sops];

  options.security.sops = {
    enable = mkEnableOption "sops";
  };

  config = mkIf cfg.enable {
    sops = {
      defaultSopsFile = "${sopsFolder}/${config.networking.hostName}/secrets.yaml";
      validateSopsFiles = false;

      age.sshKeyPaths = ["${optionalString impermanence "/persist"}/etc/ssh/ssh_host_ed25519_key"];

      secrets = {
        "keys/age" = {
          owner = config.user.name;
          inherit (config.users.users.${config.user.name}) group;
          path = "/home/${config.user.name}/.config/sops/age/keys.txt";
        };
        "passwords/${config.user.name}" = {
          sopsFile = "${sopsFolder}/common/secrets.yaml";
          neededForUsers = true;
        };
      };
    };

    user.extraOptions = {
      hashedPasswordFile = config.sops.secrets."passwords/${config.user.name}".path;
    };

    # The containing folders are created as root and if this is the first ~/.config/ entry,
    # the ownership is busted and home-manager can't target because it can't write into .config...
    # FIXME(sops): We might not need this depending on how https://github.com/Mic92/sops-nix/issues/381 is fixed
    system.activationScripts.sopsSetAgeKeyOwnership = let
      inherit (config.users.users.${config.user.name}) name group home;
      ageFolder = "${home}/.config/sops/age";
    in ''
      mkdir -p ${ageFolder} || true
      chown -R ${name}:${group} ${home}/.config
    '';
  };
}
