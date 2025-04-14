{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.development.direnv;
in {
  options.modules.development.direnv = {
    enable = lib.mkEnableOption "direnv";
  };

  config = lib.mkIf cfg.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    modules.persist.directories = [".local/share/direnv"];

    xdg.configFile."direnv/direnv.toml".source = (pkgs.formats.toml {}).generate "direnv-config" {
      hide_env_diff = true;
    };
  };
}
