# termux — `nix build .#termux-ssh`: SSH client setup for Termux on panther (Keystore key via tergent, fleet host keys pinned); see docs/src/networking.md.
{
  cosmosLib,
  den,
  lib,
  ...
}: let
  hosts = lib.mergeAttrsList (lib.attrValues den.hosts);
  # Hand-synced with cosmos.services.netbird.dnsDomain, as in den/schema.nix.
  meshName = name: "${name}.nb.lvdar.nl";
  userOf = h: (lib.head (lib.attrValues h.users)).userName;

  sshConfig =
    lib.concatMapStrings (name: ''
      Host ${name} ${meshName name}
        HostName ${meshName name}
        User ${userOf hosts.${name}}
        Port 2222
        UserKnownHostsFile ~/.ssh/known_hosts.fleet
        StrictHostKeyChecking yes

    '') (lib.attrNames hosts)
    + ''
      # services.coding-agents' user; hand-synced with endeavour's includes.
      Host agent
        HostName ${meshName "endeavour"}
        User agent
        Port 2222
        UserKnownHostsFile ~/.ssh/known_hosts.fleet
        StrictHostKeyChecking yes

      Host *
        # No IdentitiesOnly: it drops PKCS#11 keys not named by an IdentityFile.
        PKCS11Provider /data/data/com.termux/files/usr/lib/libtergent.so
        ServerAliveInterval 30
    '';

  knownHosts = lib.concatStrings (lib.mapAttrsToList (name: h: ''
    ${meshName name},[${meshName name}]:2222 ${h.sshHostKey}
  '') (lib.filterAttrs (_: h: h.sshHostKey != null) hosts));
in {
  perSystem = {pkgs, ...}: {
    packages.termux-ssh =
      pkgs.runCommand "termux-ssh" {
        config = sshConfig;
        inherit knownHosts;
        passAsFile = ["config" "knownHosts"];
      } ''
        mkdir $out
        cp $configPath $out/config
        cp $knownHostsPath $out/known_hosts.fleet
        cp ${cosmosLib.get-flake-path "modules/meta/_termux/install.sh"} $out/install.sh
      '';
  };
}
