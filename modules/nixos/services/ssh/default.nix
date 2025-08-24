{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.services.ssh;
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
          path = "/etc/ssh/ssh_host_ed25519_key";
          rounds = 100;
          type = "ed25519";
        }
      ];

      settings = {
        PasswordAuthentication = false;
        StreamLocalBindUnlink = "yes";
        GatewayPorts = "clientspecified";
      };
    };

    users.users.${config.user.name} = {
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFnXEMwtpJCNJ5gHCEmiKxuohPGyf17Ub1VT2ESXuFi larsvandartel73@gmail.com" # TODO: Regenerate with new email
      ];
    };
  };
}
