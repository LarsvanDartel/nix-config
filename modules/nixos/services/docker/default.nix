{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.docker;
in {
  options.cosmos.services.docker = {
    enable = mkEnableOption "docker";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = ["/var/lib/docker"];

    virtualisation.docker = {
      enable = true;
    };

    cosmos.user.extraGroups = ["docker"];
  };
}
