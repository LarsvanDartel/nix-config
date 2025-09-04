{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.ripgrep;
in {
  options.cli.programs.ripgrep = {
    enable = mkEnableOption "ripgrep";
  };

  config = mkIf cfg.enable {
    programs.ripgrep = {
      enable = true;
      arguments = [
        "--colors=line:style:bold"
        "--hidden"
        "--line-number"
        "--no-heading"
        "--color=always"
        "--smart-case"
        "--glob=!*.{jpg,jpeg,png,gif,svg}"
      ];
    };
  };
}
