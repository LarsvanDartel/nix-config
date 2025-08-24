{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.custom) get-non-default-nix-files;
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.styling;
in {
  imports = [inputs.stylix.homeModules.stylix] ++ get-non-default-nix-files ./.;

  options.styling = {
    enable = mkEnableOption "styling configuration";
  };

  config = mkIf cfg.enable {
    stylix = {
      enable = true;
      autoEnable = true;
      opacity.terminal = 1.0;

      # TODO: Move to cursor module
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 22;
      };
    };
  };
}
