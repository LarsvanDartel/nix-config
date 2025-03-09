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
  };

  config = lib.mkIf cfg.enable {
    security.sudo = {
      enable = true;
      extraConfig = ''
        Defaults  lecture="never"
      '';
    };
  };
}
