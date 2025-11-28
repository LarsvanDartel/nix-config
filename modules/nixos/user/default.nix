{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.cosmos) get-flake-path;
  inherit (lib.types) nullOr listOf str attrs;
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkMerge mkForce;

  cfg = config.cosmos.user;
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  options.cosmos.user = {
    name = mkOption {
      type = str;
      default = "lvdar";
      description = "Username of the main user.";
    };
    initialPassword = mkOption {
      type = nullOr str;
      default = null;
      description = "Initial password of the main user.";
    };
    extraGroups = mkOption {
      type = listOf str;
      default = [];
      description = "Extra groups for the main user.";
    };
    extraOptions = mkOption {
      type = attrs;
      default = {};
      description = "Extra options for the main user.";
    };
    extraConfig = mkOption {
      type = attrs;
      default = {};
      description = "Extra home manager options for the main user";
    };
  };

  config = {
    users = {
      mutableUsers = false;

      users.${cfg.name} =
        {
          isNormalUser = true;
          inherit (cfg) name initialPassword;
          home = "/home/${cfg.name}";
          createHome = true;
          shell = pkgs.zsh;

          extraGroups = ["wheel"] ++ cfg.extraGroups;
        }
        // cfg.extraOptions;

      users.root = {
        inherit
          (config.users.users.${cfg.name})
          hashedPassword
          hashedPasswordFile
          shell
          ;
        openssh.authorizedKeys =
          config.users.users.${cfg.name}.openssh.authorizedKeys;
      };
    };

    home-manager.backupFileExtension = "bak";
    home-manager.users = {
      ${cfg.name} = let
        host = config.networking.hostName;
      in
        mkMerge [
          (get-flake-path "homes/${cfg.name}@${host}")
          {
            cosmos.user = {
              inherit (cfg) name;
            };
            cosmos.system.impermanence.enable = mkForce config.cosmos.system.impermanence.enable;
          }
          cfg.extraConfig
        ];

      root = {
        cosmos = {
          profiles.common.enable = true;

          user = {
            name = "root";
          };

          system.impermanence.enable = mkForce config.cosmos.system.impermanence.enable;
        };

        home.stateVersion = "24.11";
      };
    };
  };
}
