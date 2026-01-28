{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.simplelogin;
in {
  options.cosmos.cli.programs.simplelogin = {
    enable = mkEnableOption "simplelogin";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".config/simplelogin-cli"];
    home.packages = [pkgs.simplelogin-cli];
  };
}
