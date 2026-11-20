# abort-on-warn — turns eval warnings into hard errors via the generated flake.nix's nixConfig.
{...}: {
  flake-file.nixConfig.abort-on-warn = true;
}
