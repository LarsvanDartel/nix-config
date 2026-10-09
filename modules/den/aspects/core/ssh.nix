# core.ssh — openssh server + authorized keys for the primary user and root.
{cosmosLib, ...}: let
  inherit (cosmosLib) get-files get-flake-path;

  keys = get-files (get-flake-path "modules/den/aspects/core/_ssh-keys");
in {
  den.aspects.core.ssh.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (builtins) readFile;
    inherit (lib.strings) optionalString;

    active = config.cosmos.system.impermanence.active;
    userName = config.cosmos.user.name;
    keyList = map readFile keys;
  in {
    programs.ssh.startAgent = true;
    services.openssh = {
      enable = true;

      # 2222 because NetBird's SSH server hijacks <netbird-ip>:22 (presents as
      # "Permission denied (password)"); deploy-rs needs OpenSSH via the mesh.
      ports = [22 2222];
      hostKeys = [
        {
          comment = "${config.networking.hostName}.local";
          path = "${optionalString active "/persist"}/etc/ssh/ssh_host_ed25519_key";
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

    users.users.${userName}.openssh.authorizedKeys.keys = keyList;
    users.users.root.openssh.authorizedKeys.keys = keyList;
  };
}
