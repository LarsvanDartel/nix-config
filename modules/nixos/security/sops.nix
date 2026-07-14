{inputs, ...}: {
  flake-file.inputs = {
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-secrets.url = "git+ssh://git@github.com/LarsvanDartel/nix-secrets.git?shallow=1";
  };

  flake.modules.nixos.common = {
    config,
    lib,
    ...
  }: let
    inherit (lib.strings) optionalString;

    sopsFolder = builtins.toString inputs.nix-secrets + "/hosts";
    active = config.cosmos.system.impermanence.active;
    userName = config.cosmos.user.name;
  in {
    imports = [inputs.sops-nix.nixosModules.sops];

    config = {
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

      cosmos.user.extraOptions = {
        hashedPasswordFile = config.sops.secrets."passwords/${userName}".path;
      };

      # The containing folders are created as root and if this is the first ~/.config/ entry,
      # the ownership is busted and home-manager can't target because it can't write into .config...
      # FIXME(sops): We might not need this depending on how https://github.com/Mic92/sops-nix/issues/381 is fixed
      system.activationScripts.sopsSetAgeKeyOwnership = let
        inherit (config.users.users.${userName}) name group home;
        ageFolder = "${home}/.config/sops/age";
      in ''
        mkdir -p ${ageFolder} || true
        chown -R ${name}:${group} ${home}/.config
      '';
    };
  };
}
