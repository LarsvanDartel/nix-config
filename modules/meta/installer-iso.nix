# installer-iso — NixOS minimal installer (latest kernel, no ZFS) that the fleet's admin keys can reach as root; boot targets of install-host from it.
{
  inputs,
  cosmosLib,
  lib,
  ...
}: let
  keysDir = cosmosLib.get-flake-path "modules/den/aspects/core/_ssh-keys";
  authorizedKeys = map (f: builtins.readFile (keysDir + "/${f}")) (import (keysDir + "/authorized.nix"));
in {
  perSystem = {system, ...}: {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      installer-iso =
        (inputs.nixpkgs.lib.nixosSystem {
          modules = [
            "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal-new-kernel-no-zfs.nix"
            ({pkgs, ...}: {
              nixpkgs.hostPlatform = system;
              networking.hostName = "cosmos-installer";
              # install-host refuses targets without this marker.
              environment.etc.cosmos-installer.text = "";
              users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
              environment.systemPackages = with pkgs; [nixos-facter git pv];
              nix.settings.experimental-features = ["nix-command" "flakes"];
              services.getty.helpLine = lib.mkAfter ''

                cosmos installer — IPv4: \4
                From a fleet machine: nix run .#install-host -- install <host> \4 --host-key <key>
              '';
            })
          ];
        }).config.system.build.isoImage;
    };
  };
}
