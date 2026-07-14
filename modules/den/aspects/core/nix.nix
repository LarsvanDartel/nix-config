# core.nix aspect — nix daemon settings (was flake.modules.nixos.common in
# modules/nixos/system/nix.nix). allowUnfree lives in core.nixpkgs.
{...}: {
  den.aspects.core.nix.nixos = {lib, ...}: {
    nix.settings = {
      trusted-users = ["@wheel" "root"];
      auto-optimise-store = lib.mkDefault true;
      use-xdg-base-directories = true;
      experimental-features = ["nix-command" "flakes"];
      warn-dirty = false;
    };
  };
}
