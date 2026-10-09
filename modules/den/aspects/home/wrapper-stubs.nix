# home.wrapper-stubs — cosmos.* option stubs so aspects evaluate in isolation in
# the wrapped-package catalog. Values set here go nowhere.
{...}: {
  den.aspects.home.wrapper-stubs.homeManager = {lib, ...}: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str lines attrsOf listOf coercedTo bool;
  in {
    options.cosmos = {
      cli.shells.zsh = {
        aliases = mkOption {
          type = attrsOf str;
          default = {};
        };
        initContent = mkOption {
          type = lines;
          default = "";
        };
      };
      system.impermanence = {
        active = mkOption {
          type = bool;
          default = false;
        };
        persist = {
          files = mkOption {
            type = listOf (coercedTo str (f: {file = f;}) (attrsOf str));
            default = [];
          };
          directories = mkOption {
            type = listOf (coercedTo str (d: {directory = d;}) (attrsOf str));
            default = [];
          };
        };
      };
    };
  };
}
