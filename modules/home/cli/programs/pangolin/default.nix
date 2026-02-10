{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.pangolin;
in {
  options.cosmos.cli.programs.pangolin = {
    enable = mkEnableOption "pangolin";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".config/pangolin"];
    home.packages = [pkgs.pangolin-cli];
  };
}
