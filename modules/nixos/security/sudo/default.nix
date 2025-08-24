{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.security.sudo-config;
in {
  options.security.sudo-config = {
    enable = mkEnableOption "sudo" // {default = true;};
    lecture = mkEnableOption "sudo lecture";
  };

  config = lib.mkIf cfg.enable {
    system.impermanence.persist.directories = [
      "/var/db/sudo"
    ];
    security.sudo = {
      enable = true;
      extraConfig = mkIf (!cfg.lecture) ''
        Defaults lecture="never"
      '';
    };
  };
}
