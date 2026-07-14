# System-level user record. The home-manager wiring that used to live here is
# now done per-host (each host imports the home features it wants into
# `home-manager.users.<name>`), so this feature only owns the NixOS user.
{...}: {
  flake.modules.nixos.common = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.types) nullOr listOf str attrs;
    inherit (lib.options) mkOption;

    cfg = config.cosmos.user;
  in {
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
        description = "Extra options for the main user (merged into the user record).";
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
    };
  };
}
