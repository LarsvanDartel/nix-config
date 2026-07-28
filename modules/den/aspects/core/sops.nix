# core.sops — sops-nix + per-host secrets, user password, age key ownership.
# Owns the sops-nix + nix-secrets inputs (home.core also references sops-nix).
{inputs, ...}: {
  flake-file.inputs = {
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-secrets.url = "git+ssh://git@github.com/LarsvanDartel/nix-secrets.git?shallow=1";
  };

  den.aspects.core.sops.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.strings) optionalString;

    sopsFolder = builtins.toString inputs.nix-secrets + "/hosts";
    active = config.cosmos.system.impermanence.active;
    userName = config.cosmos.user.name;
    passwordPath = config.sops.secrets."passwords/${userName}".path;
  in {
    imports = [inputs.sops-nix.nixosModules.sops];

    sops = {
      defaultSopsFile = "${sopsFolder}/${config.networking.hostName}/secrets.yaml";
      validateSopsFiles = false;

      age.sshKeyPaths = ["${optionalString active "/persist"}/etc/ssh/ssh_host_ed25519_key"];

      secrets = {
        "keys/age" = {
          owner = userName;
          inherit (config.users.users.${userName}) group;
          path = "/home/${userName}/.config/sops/age/keys.txt";
        };
        "passwords/${userName}" = {
          sopsFile = "${sopsFolder}/common/secrets.yaml";
          neededForUsers = true;
        };
      };
    };

    users.users.${userName}.hashedPasswordFile = passwordPath;
    users.users.root.hashedPasswordFile = passwordPath;

    system.activationScripts.sopsSetAgeKeyOwnership = let
      inherit (config.users.users.${userName}) name group home;
      ageFolder = "${home}/.config/sops/age";
    in ''
      mkdir -p ${ageFolder} || true
      chown -R ${name}:${group} ${home}/.config
    '';
  };
}
