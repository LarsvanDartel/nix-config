{
  config,
  lib,
  ...
}: let
  cfg = config.modules.sudo;
in {
  options.modules.sudo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable sudo.";
    };
    lecture = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to lecture users on sudo.";
    };
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      "/var/db/sudo"
    ];
    security.sudo = {
      enable = true;
      extraConfig = lib.mkIf (!cfg.lecture) ''
        Defaults  lecture="never"
      '';
    };
  };
}
