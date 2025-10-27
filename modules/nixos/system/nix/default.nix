{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.system.nix;
in {
  options.cosmos.system.nix = {
    enable = mkEnableOption "nix configuration";
  };

  config = mkIf cfg.enable {
    nix = {
      settings = {
        trusted-users = ["@wheel" "root"];
        auto-optimise-store = lib.mkDefault true;
        use-xdg-base-directories = true;
        experimental-features = ["nix-command" "flakes"];
        warn-dirty = false;
      };
    };
    nixpkgs.config.allowUnfree = true;
  };
}
