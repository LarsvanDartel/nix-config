{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.custom) get-flake-path;
  inherit (lib.types) listOf str attrs;
  inherit (lib.options) mkOption;
  inherit (lib.modules) mkMerge;

  cfg = config.user;
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  options.user = {
    name = mkOption {
      type = str;
      default = "lvdar";
      description = "Username of the main user.";
    };
    initialPassword = mkOption {
      type = str;
      default = "pwd";
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
  };

  config = {
    users = {
      mutableUsers = false;

      users.${cfg.name} =
        {
          isNormalUser = true;
          inherit (cfg) name initialPassword;
          home = "/home/${cfg.name}";
          shell = pkgs.zsh;

          extraGroups = ["wheel"] ++ cfg.extraGroups;
        }
        // cfg.extraOptions;

      users.root = {
        shell = pkgs.zsh;
        inherit (config.users.users.${cfg.name}) hashedPassword hashedPasswordFile;
        openssh.authorizedKeys = config.users.users.${cfg.name}.openssh.authorizedKeys;
      };
    };

    home-manager.users.${cfg.name} = let
      host = config.networking.hostName;
    in
      mkMerge [
        (get-flake-path "homes/${cfg.name}@${host}")
        {
          user = {
            enable = true;
            inherit (cfg) name;
          };
        }
      ];

    home-manager.users.root = {
      profiles.common.enable = true;

      home = {
        username = "root";
        homeDirectory = "/root";
      };

      home.stateVersion = "24.11";
    };
  };
}
