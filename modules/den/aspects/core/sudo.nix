# core.sudo — sudo config + the lecture option (was flake.modules.nixos.common
# in modules/nixos/security/sudo.nix).
{...}: {
  den.aspects.core.sudo.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkEnableOption;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.security.sudo-config;
  in {
    options.cosmos.security.sudo-config = {
      lecture = mkEnableOption "sudo lecture";
    };

    config = {
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
  };
}
