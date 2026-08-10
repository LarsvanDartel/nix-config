# core.ssh — openssh server + authorized keys for the primary user and root
# (was flake.modules.nixos.common in modules/nixos/services/ssh/default.nix).
# Keys live in ./_ssh-keys (import-tree-ignored).
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

      # 2222 exists because NetBird's own SSH server takes 22 away on the mesh.
      # Its agent redirects <netbird-ip>:22 to its embedded server on :22022
      # (client/internal/engine_ssh.go), so once a peer has ssh_enabled every
      # connection to <host>.nb.lvdar.nl:22 reaches that server instead of this
      # one — a different host key, and no interest in the keys below, since it
      # authenticates through NetBird. It presents as "Permission denied
      # (password)" and, for anything that had connected before, a host key
      # warning.
      #
      # That server is wanted (`netbird ssh <peer>` is the point of it), but it
      # cannot be the only way in: deploy-rs reaches these hosts by their mesh
      # name and authenticates as root with a key, and OpenSSH is what has to
      # answer that. The redirect is specific to :22, so a second port is
      # enough, and both servers coexist — netbird's on the mesh's :22, this
      # one everywhere else and on :2222 throughout.
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
