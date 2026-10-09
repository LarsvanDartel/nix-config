{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.types) listOf str;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.strings) hasSuffix;

  cfg = config.cosmos.desktops.hyprland;

  # import-tree ignores this _impl dir.
  nonDefault = dir:
    map (n: dir + "/${n}")
    (builtins.attrNames (filterAttrs (n: t: t == "regular" && n != "default.nix" && hasSuffix ".nix" n) (builtins.readDir dir)));
in {
  imports = nonDefault ./.;

  options.cosmos.desktops.hyprland = {
    # Part-files self-gate on this, hence default true.
    enable = mkEnableOption "hyprland" // {default = true;};

    exec-once-extras = mkOption {
      type = listOf str;
      default = [];
      description = "Extra commands to run once on Hyprland startup.";
    };
  };

  config = mkIf cfg.enable {
    nix.settings = {
      trusted-substituters = ["https://hyprland.cachix.org"];
      extra-trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };

    home.packages = with pkgs; [
      brightnessctl
      wl-clipboard
    ];
  };
}
