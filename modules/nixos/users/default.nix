{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkOption mkPackageOption;
  inherit (lib.types) submodule bool path listOf str attrsOf;
  inherit (lib.modules) mkIf;
  inherit (lib.attrsets) concatMapAttrs;

  userModule = submodule {
    options = {
      sudo = mkOption {
        type = bool;
        default = false;
        example = true;
        description = "Whether the user is allowed sudo access.";
      };
      config = mkOption {
        type = path;
        description = "Home manager config for this user.";
      };
      shell = mkPackageOption pkgs "shell" {
        default = "bash";
        example = "zsh";
      };
    };
  };
in {
  imports = [
    ./systemwide.nix
  ];

  options = {
    host.sudo-groups = lib.mkOption {
      type = listOf str;
      default = [];
      description = "Additional groups assigned to sudo users.";
    };
    host.users = mkOption {
      type = attrsOf userModule;
      default = {};
      description = "User configurations for this host";
    };
  };

  config = {
    users.users =
      concatMapAttrs (name: value: {
        ${name} = {
          inherit (value) shell;
          isNormalUser = true;
          extraGroups = mkIf value.sudo (["wheel"] ++ config.host.sudo-groups);
          initialPassword = "pwd";
        };
      })
      config.host.users;

    home-manager.users =
      concatMapAttrs (name: value: {
        ${name} = value.config;
      })
      config.host.users;

    nix.settings.trusted-users = lib.attrNames config.host.users;
  };
}
