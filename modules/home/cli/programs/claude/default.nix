{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.claude;
in {
  options.cosmos.cli.programs.claude = {
    enable = mkEnableOption "claude";
  };

  config = mkIf cfg.enable {
    home.packages = [pkgs.claude-code];

    cosmos.system.impermanence.persist = {
      files = [".claude.json"];
      directories = [".claude"];
    };
  };
}
