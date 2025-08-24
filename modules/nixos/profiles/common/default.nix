{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.profiles.common;
in {
  options.profiles.common = {
    enable = mkEnableOption "common configuration";
  };

  config = mkIf cfg.enable {
    hardware = {
      networking.enable = true;
    };

    programs = {
      git.enable = true;
      zsh.enable = true;
    };

    services = {
      ssh.enable = true;
    };

    security = {
      sops.enable = true;
      yubikey.enable = true;
    };

    system = {
      nix.enable = true;
      boot.enable = true;
      locale.enable = true;
    };
  };
}
