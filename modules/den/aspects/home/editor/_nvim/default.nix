{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.strings) hasSuffix;

  # import-tree ignores this _impl dir.
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
