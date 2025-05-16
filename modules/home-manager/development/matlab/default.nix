{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) nullOr str;

  cfg = config.modules.development.matlab;
in {
  options.modules.development.matlab = {
    enable = mkEnableOption "Enable MATLAB development environment";
    matlabPath = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        Path to the MATLAB installation directory.
        This is used to set up the MATLAB environment.
      '';
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [inputs.nix-matlab.overlay];

    modules.persist.directories = [cfg.matlabPath];

    home.packages = with pkgs; [
      matlab
    ];

    home.file.".config/matlab/nix.sh" = {
      text = ''
        INSTALL_DIR=$HOME/${cfg.matlabPath}
      '';
      executable = true;
    };
  };
}
