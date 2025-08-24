{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.ssh;
in {
  options.cli.programs.ssh = {
    enable = mkEnableOption "ssh";
  };

  config = mkIf cfg.enable {
    programs.keychain = {
      enable = true;
      keys = ["id_ed25519"];
    };

    programs.ssh = {
      enable = true;
      addKeysToAgent = "yes";
    };
  };
}
