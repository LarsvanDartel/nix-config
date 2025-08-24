{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.system.nix;
in {
  options.system.nix = {
    enable = mkEnableOption "nix configuration";
  };

  config = mkIf cfg.enable {
    programs.home-manager.enable = true;

    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        warn-dirty = false;
        use-xdg-base-directories = true;
      };
    };

    nixpkgs.config = {
      allowUnfree = true;
    };
  };
}
