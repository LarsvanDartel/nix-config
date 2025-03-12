{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib; let
  userModule = types.submodule {
    options = {
      sudo = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = "Whether the user is allowed sudo access.";
      };
      config = mkOption {
        type = types.path;
        description = "Home manager config for this user.";
      };
    };
  };
in {
  options = {
    host.sudo-groups = lib.mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional groups assigned to sudo users.";
    };
    host.users = mkOption {
      type = types.attrsOf userModule;
      default = {};
      description = "User configurations for this host";
    };
  };

  config = {
    users.users =
      attrsets.concatMapAttrs (name: value: {
        ${name} = {
          isNormalUser = true;
          extraGroups = mkIf value.sudo (["wheel"] ++ config.host.sudo-groups);
          initialPassword = "pwd";
        };
      })
      config.host.users;

    home-manager.sharedModules = [
      inputs.self.outputs.homeManagerModules.default
    ];

    home-manager.users =
      attrsets.concatMapAttrs (name: value: {
        ${name} = value.config;
      })
      config.host.users;
  };
}
