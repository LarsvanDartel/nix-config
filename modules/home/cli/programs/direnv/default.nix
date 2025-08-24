{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.direnv;
in {
  options.cli.programs.direnv = {
    enable = mkEnableOption "direnv";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [".local/share/direnv"];

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    xdg.configFile."direnv/direnv.toml".source = (pkgs.formats.toml {}).generate "direnv-config" {
      hide_env_diff = true;
    };
  };
}
