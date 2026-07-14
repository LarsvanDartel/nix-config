# Home impermanence activation. The `home.persistence` option is provided by
# the impermanence home-manager module, which the nixos impermanence feature
# injects via home-manager.sharedModules. Import this into a user's home only
# on impermanent hosts.
{...}: {
  flake.modules.homeManager.impermanence = {config, ...}: {
    cosmos.system.impermanence.active = true;

    home.persistence."/persist" = {
      inherit (config.cosmos.system.impermanence.persist) files directories;
    };
  };
}
