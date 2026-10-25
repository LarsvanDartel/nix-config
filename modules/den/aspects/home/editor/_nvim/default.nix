# nvim — the nixvim configuration (standalone nixvim modules, built by ../nvim.nix).
{
  config,
  lib,
  ...
}: let
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.strings) hasSuffix;

  # import-tree ignores this _impl dir. settings.nix is a submodule, not a nixvim module.
  nonDefault = dir:
    map (n: dir + "/${n}")
    (builtins.attrNames (filterAttrs (n: t: t == "regular" && n != "default.nix" && n != "settings.nix" && hasSuffix ".nix" n) (builtins.readDir dir)));
in {
  imports =
    [
      ./languages
      ./plugins
    ]
    ++ nonDefault ./.;

  options.cosmos.nvim = lib.mkOption {
    type = lib.types.submodule ./settings.nix;
    default = {};
  };

  config.waylandSupport = config.cosmos.nvim.wayland;
}
