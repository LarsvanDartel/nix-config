# Custom helpers, injected as the `cosmosLib` module arg (via _module.args) so
# any flake-parts module can take {cosmosLib, ...}.
{lib, ...}: let
  inherit (lib.attrsets) filterAttrs mapAttrsToList attrNames;
  inherit (lib.lists) init length;
  inherit (lib.strings) concatStringsSep splitString;

  regularFiles = path: filterAttrs (_: kind: kind == "regular") (builtins.readDir path);
in {
  _module.args.cosmosLib = {
    get-flake-path = lib.path.append ../../.;

    get-files = path: mapAttrsToList (name: _: "${path}/${name}") (regularFiles path);

    get-file-names = path: attrNames (regularFiles path);

    get-file-name-without-extension = path: let
      base = baseNameOf path;
      parts = splitString "." base;
    in
      if length parts > 1
      then concatStringsSep "." (init parts)
      else base;
  };
}
