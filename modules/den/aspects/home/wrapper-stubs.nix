# home.wrapper-stubs — declares the cross-cutting cosmos.* options that some home
# aspects write to (zsh init/aliases, impermanence persist) so they can be
# evaluated in ISOLATION for the wrapped-package catalog (where the aspects that
# normally declare those options aren't present). Values set here go nowhere —
# this is only about making the option exist. Added to hmWrappers.baseModules.
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
