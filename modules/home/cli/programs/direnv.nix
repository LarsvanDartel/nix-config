# direnv. The program + config split into a named module for wrapping; the
# impermanence persist entry (a cosmos option that doesn't exist in an isolated
# wrap eval) stays in `common`.
{config, ...}: {
  flake.modules.homeManager.direnv = {pkgs, ...}: {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    xdg.configFile."direnv/direnv.toml".source = (pkgs.formats.toml {}).generate "direnv-config" {
      hide_env_diff = true;
    };
  };

  flake.modules.homeManager.common = {
    imports = [config.flake.modules.homeManager.direnv];
    cosmos.system.impermanence.persist.directories = [".local/share/direnv"];
  };
}
