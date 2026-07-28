# home.direnv (+ its impermanence persist entry)
{...}: {
  den.aspects.home.direnv.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".local/share/direnv"];

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    xdg.configFile."direnv/direnv.toml".source = (pkgs.formats.toml {}).generate "direnv-config" {
      hide_env_diff = true;
    };
  };
}
