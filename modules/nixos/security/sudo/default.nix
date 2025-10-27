{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.security.sudo-config;
in {
  options.cosmos.security.sudo-config = {
    enable = mkEnableOption "sudo" // {default = true;};
    lecture = mkEnableOption "sudo lecture";
  };

  config = lib.mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
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
