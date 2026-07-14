# Custom helpers, injected as the `cosmosLib` module arg (via _module.args) so
# any flake-parts module can take `{cosmosLib, ...}`. Replaces the old
# flake.lib.cosmos export. Only the helpers still in use survive here.
{lib, ...}: let
  inherit (lib.attrsets) filterAttrs mapAttrsToList attrNames;
  inherit (lib.lists) init length;
  inherit (lib.strings) concatStringsSep splitString;

  regularFiles = path: filterAttrs (_: kind: kind == "regular") (builtins.readDir path);
in {
  _module.args.cosmosLib = {
    # Path to a subpath of the flake root (a genuine path, usable as a
    # `source`/`fileContents` argument).
    get-flake-path = lib.path.append ../../.;

    # List of regular-file paths directly inside `path`.
    get-files = path: mapAttrsToList (name: _: "${path}/${name}") (regularFiles path);

    # List of regular-file names directly inside `path`.
    get-file-names = path: attrNames (regularFiles path);

    # Basename of `path` with its final extension removed.
    get-file-name-without-extension = path: let
      base = baseNameOf path;
      parts = splitString "." base;
    in
      if length parts > 1
      then concatStringsSep "." (init parts)
      else base;
  };
}
