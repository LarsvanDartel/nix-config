# core.ssh — sshd on :2222, the admin keys (_ssh-keys/authorized.nix) for root and the primary user, and every fleet host key pinned system-wide.
{
  cosmosLib,
  den,
  lib,
  ...
}: let
  keysDir = cosmosLib.get-flake-path "modules/den/aspects/core/_ssh-keys";
  authorizedKeys = map (f: builtins.readFile (keysDir + "/${f}")) (import (keysDir + "/authorized.nix"));

  hosts = lib.mergeAttrsList (lib.attrValues den.hosts);
  knownHosts =
    lib.mapAttrs (name: h: {
      # <name>.nb.lvdar.nl is what home.ssh connects to; gaia's deployAddress differs.
      hostNames = lib.unique (
        lib.concatMap (a: [a "[${a}]:2222"]) ([h.deployAddress "${name}.nb.lvdar.nl"] ++ lib.optional (h.meshAddress != null) h.meshAddress)
        ++ [name]
      );
      publicKey = h.sshHostKey;
    })
    (lib.filterAttrs (_: h: h.sshHostKey != null) hosts)
    // {
      # knot2's own key (/tank/knot/ssh_host_key on endeavour), not endeavour's:
      # knot.lvdar.nl:22 is gaia's DNAT to the knot's in-process SSH. Hand-synced.
      "knot.lvdar.nl" = {
        hostNames = ["knot.lvdar.nl" "[endeavour.nb.lvdar.nl]:2223"];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEg3hdiuWPVdxL9izERD+jzYhrLr4RPcbqcCOgjvt/6f";
      };
    };
in {
  den.aspects.core.ssh.nixos = {config, ...}: let
    inherit (lib.strings) optionalString;

    active = config.cosmos.system.impermanence.active;
    userName = config.cosmos.user.name;
  in {
    services.openssh = {
      enable = true;

      # NetBird's SSH server owns <mesh-ip>:22; nothing used :22 elsewhere.
      ports = [2222];
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
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };

    users.users.${userName}.openssh.authorizedKeys.keys = authorizedKeys;
    users.users.root.openssh.authorizedKeys.keys = authorizedKeys;

    programs.ssh.knownHosts = knownHosts;
  };
}
