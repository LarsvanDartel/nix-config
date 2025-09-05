{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.services.docker;
in {
  options.services.docker = {
    enable = mkEnableOption "docker";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = ["/var/lib/docker"];

    virtualisation.docker = {
      enable = true;
    };

    user.extraGroups = ["docker"];
  };
}
