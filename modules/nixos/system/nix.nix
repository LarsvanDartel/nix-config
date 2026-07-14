{...}: {
  flake.modules.nixos.common = {lib, ...}: {
    nix.settings = {
      trusted-users = ["@wheel" "root"];
      auto-optimise-store = lib.mkDefault true;
      use-xdg-base-directories = true;
      experimental-features = ["nix-command" "flakes"];
      warn-dirty = false;
    };
    # allowUnfree is set on the shared per-system pkgs instance (withSystem),
    # so it must not be set here (nixpkgs.config is rejected with external pkgs).
  };
}
