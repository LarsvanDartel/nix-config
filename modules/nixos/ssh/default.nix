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
    programs.ssh.startAgent = true;
    services.openssh = {
      enable = true;
      hostKeys = [
        {
          comment = "${config.networking.hostName}.local";
          path = "/etc/ssh/ssh_host_ed25519_key";
          rounds = 100;
          type = "ed25519";
        }
      ];
    };
  };
}
