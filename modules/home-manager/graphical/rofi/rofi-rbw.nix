{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.graphical.rofi.rofi-rbw;
in {
  options.modules.graphical.rofi.rofi-rbw = {
    enable = lib.mkEnableOption "rofi-rbw";
    email = lib.mkOption {
      type = lib.types.str;
      description = "Bitwarden email";
    };
    base_url = lib.mkOption {
      type = lib.types.str;
      description = "Bitwarden base url";
    };
    identity_url = lib.mkOption {
      type = lib.types.str;
      description = "Bitwarden identity url";
    };
  };

  config = lib.mkIf cfg.enable {
    modules.graphical.rofi.enable = true;

    home.packages = with pkgs; [
      rofi-rbw
      wtype
    ];

    programs.rbw = {
      enable = true;
      settings = {
        inherit (cfg) email base_url identity_url;
        pinentry = pkgs.pinentry;
      };
    };
  };
}
