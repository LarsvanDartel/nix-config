{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.strings) hasSuffix;

  # Sibling non-default .nix files (import-tree ignores this whole _impl dir, so
  # they are pulled in explicitly here rather than globally).
  nonDefault = dir:
    map (n: dir + "/${n}")
    (builtins.attrNames (filterAttrs (n: t: t == "regular" && n != "default.nix" && hasSuffix ".nix" n) (builtins.readDir dir)));
in {
  imports =
    [
      inputs.nixvim.homeModules.nixvim
      ./languages
      ./plugins
    ]
    ++ nonDefault ./.;

  options.cosmos.cli.programs.nvim.wayland = mkEnableOption "wayland clipboard support in nvim";

  config.programs.nixvim = {
    enable = true;
    defaultEditor = true;

    nixpkgs.useGlobalPackages = true;

    waylandSupport = config.cosmos.cli.programs.nvim.wayland;
  };
}
