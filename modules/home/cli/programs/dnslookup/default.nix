{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.dnslookup;
in {
  options.cosmos.cli.programs.dnslookup = {
    enable = mkEnableOption "dnslookup";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      dnslookup
    ];
  };
}
