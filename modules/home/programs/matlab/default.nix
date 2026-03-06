{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.programs.matlab;
in {
  options.cosmos.programs.matlab = {
    enable = mkEnableOption "matlab";
  };
  config = mkIf cfg.enable {
    home.file.".config/matlab/nix.sh".text = ''
      INSTALL_DIR=${config.home.homeDirectory}/downloads/software/matlab/installation
    '';
    home.packages = [pkgs.matlab];

    cosmos.system.impermanence.persist.directories = ["downloads/software/matlab"];
  };
}
