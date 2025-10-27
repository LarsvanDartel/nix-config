{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.direnv;
in {
  options.cosmos.cli.programs.direnv = {
    enable = mkEnableOption "direnv";
  };

  config = mkIf cfg.enable {
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
