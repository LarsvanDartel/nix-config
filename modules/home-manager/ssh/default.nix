{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.ssh;
in {
  options.modules.ssh = {
    enable = lib.mkEnableOption "ssh";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      ".ssh"
    ];
    programs.ssh = {
      enable = true;
      addKeysToAgent = "yes";
    };
  };
}
