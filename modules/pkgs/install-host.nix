# install-host — `nix run .#install-host -- keygen|install …`: host keys and nixos-anywhere installs from the cosmos installer ISO.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      install-host = final.writeShellApplication {
        name = "install-host";
        # No nix: it uses the system nix and its config.
        runtimeInputs = with final; [nixos-anywhere ssh-to-age sops openssh git jq pv gnutar coreutils systemd];
        text = builtins.readFile ./_install-host/install-host.sh;
      };
    })
  ];

  perSystem = {pkgs, ...}: {packages.install-host = pkgs.install-host;};
}
