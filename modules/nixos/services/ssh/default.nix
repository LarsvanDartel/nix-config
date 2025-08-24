{
  config,
  lib,
  ...
}: let
  inherit (builtins) readFile;
  inherit (lib.custom) get-files;
  inherit (lib.lists) map;
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.strings) optionalString;

  cfg = config.services.ssh;
  impermanence = config.system.impermanence.enable;

  keys = get-files ./keys;
in {
  options.services.ssh = {
    enable = mkEnableOption "ssh";
  };

  config = mkIf cfg.enable {
    programs.ssh.startAgent = true;
    services.openssh = {
      enable = true;
      hostKeys = [
        {
          comment = "${config.networking.hostName}.local";
          path = "${optionalString impermanence "/persist"}/etc/ssh/ssh_host_ed25519_key";
          rounds = 100;
          type = "ed25519";
        }
      ];

      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "yes";
        StreamLocalBindUnlink = "yes";
        GatewayPorts = "clientspecified";
      };
    };

    users.users.${config.user.name} = {
      openssh.authorizedKeys.keys = map readFile keys;
    };
  };
}
