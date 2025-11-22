{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.cosmos) get-non-default-nix-files;
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim;
in {
  imports =
    [
      inputs.nixvim.homeModules.nixvim
    ]
    ++ get-non-default-nix-files ./.;

  options.cosmos.cli.programs.nvim = {
    enable = mkEnableOption "nvim";
  };

  config = mkIf cfg.enable {
    programs.nixvim = {
      enable = true;
      defaultEditor = true;

      nixpkgs.useGlobalPackages = true;

      waylandSupport = config.cosmos.desktops.hyprland.enable;
    };
  };
}
