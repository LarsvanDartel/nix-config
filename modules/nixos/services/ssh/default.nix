{cosmosLib, ...}: let
  inherit (cosmosLib) get-files;

  keys = get-files ./keys;
in {
  flake.modules.nixos.common = {
    config,
    lib,
    ...
  }: let
    inherit (builtins) readFile;
    inherit (lib.strings) optionalString;

    active = config.cosmos.system.impermanence.active;
  in {
    programs.ssh.startAgent = true;
    services.openssh = {
      enable = true;
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

    cosmos.user.extraOptions = {
      openssh.authorizedKeys.keys = map readFile keys;
    };
  };
}
