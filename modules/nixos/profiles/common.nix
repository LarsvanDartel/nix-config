# The `common` aggregate: baseline config every host imports. Individual
# baseline features (nix, boot, locale, networking, ssh, sops, sudo, yubikey,
# user, impermanence-options) self-register into `flake.modules.nixos.common`
# from their own files; this file adds the profile-level glue + the central
# home-manager wiring (so hosts no longer repeat the boilerplate).
{
  inputs,
  config,
  ...
}: let
  home = config.flake.modules.homeManager;
in {
  flake.modules.nixos.common = {config, ...}: let
    userName = config.cosmos.user.name;
  in {
    imports = [inputs.home-manager.nixosModules.home-manager];

    # System-level git/zsh (user shell + completions).
    programs.git.enable = true;
    programs.zsh.enable = true;

    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "bak";
      extraSpecialArgs = {inherit inputs;};

      # Every user's home inherits its stateVersion from the system.
      sharedModules = [
        ({osConfig, ...}: {home.stateVersion = osConfig.system.stateVersion;})
      ];

      users.${userName} = {
        imports = [home.common];
        cosmos.user.name = userName;
      };
      users.root = {
        imports = [home.common];
        cosmos.user = {
          name = "root";
          home = "/root";
        };
      };
    };
  };
}
