{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.profiles.common;
in {
  options.cosmos.profiles.common = {
    enable = mkEnableOption "common configuration";
  };

  config = mkIf cfg.enable {
    cosmos = {
      networking.enable = true;

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
    programs = {
      git.enable = true;
      zsh.enable = true;
    };
  };
}
