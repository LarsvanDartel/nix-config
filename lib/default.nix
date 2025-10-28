{lib, ...}: let
  inherit (builtins) readDir pathExists;
  inherit (lib) assertMsg;
  inherit (lib.attrsets) filterAttrs mapAttrsToList;
  inherit (lib.path) append;
  inherit (lib.lists) flatten last init;
  inherit (lib.strings) concatStringsSep;

  file-name-regex = "(.*)\\.(.*)$";
in rec {
  nginx = import ./nginx.nix {inherit lib;};

  split-file-extension = file: let
    match = builtins.match file-name-regex file;
  in
    assert assertMsg (match != null) "split-file-extension: File must have an extension to split."; match;

  has-any-file-extension = file: let
    match = builtins.match file-name-regex (toString file);
  in
    match != null;

  get-file-extension = file:
    if has-any-file-extension file
    then let
      match = builtins.match file-name-regex (toString file);
    in
      last match
    else "";

  has-file-extension = extension: file:
    if has-any-file-extension file
    then extension == get-file-extension file
    else false;

  get-file-name-without-extension = path: let
    file-name = baseNameOf path;
  in
    if has-any-file-extension file-name
    then concatStringsSep "" (init (split-file-extension file-name))
    else file-name;

  is-file-kind = kind: kind == "regular";
  is-symlink-kind = kind: kind == "symlink";
  is-directory-kind = kind: kind == "directory";
  is-unknown-kind = kind: kind == "unknown";

  get-flake-path = append ../.;

  safe-read-directory = path:
    if pathExists path
    then readDir path
    else {};

  get-directories = path: let
    entries = safe-read-directory path;
    filtered-entries = filterAttrs (_: is-directory-kind) entries;
  in
    mapAttrsToList (name: _: "${path}/${name}") filtered-entries;

  get-files = path: let
    entries = safe-read-directory path;
    filtered-entries = filterAttrs (_: is-file-kind) entries;
  in
    mapAttrsToList (name: _: "${path}/${name}") filtered-entries;

  get-files-recursive = path: let
    entries = safe-read-directory path;
    filtered-entries =
      filterAttrs
      (_: kind: (is-file-kind kind) || (is-directory-kind kind))
      entries;
    map-file = name: kind: let
      path' = "${path}/${name}";
    in
      if is-directory-kind kind
      then get-files-recursive path'
      else path';
    files = flatten (
      mapAttrsToList
      map-file
      filtered-entries
    );
  in
    files;

  get-nix-files = path:
    builtins.filter
    (has-file-extension "nix")
    (get-files path);

  get-nix-files-recursive = path:
    builtins.filter
    (has-file-extension "nix")
    (get-files-recursive path);

  get-default-nix-files = path:
    builtins.filter
    (name: builtins.baseNameOf name == "default.nix")
    (get-files path);

  get-default-nix-files-recursive = path:
    builtins.filter
    (name: builtins.baseNameOf name == "default.nix")
    (get-files-recursive path);

  get-non-default-nix-files = path:
    builtins.filter
    (
      name:
        (has-file-extension "nix" name)
        && (builtins.baseNameOf name != "default.nix")
    )
    (get-files path);

  get-non-default-nix-files-recursive = path:
    builtins.filter
    (
      name:
        (has-file-extension "nix" name)
        && (builtins.baseNameOf name != "default.nix")
    )
    (get-files-recursive path);
}
