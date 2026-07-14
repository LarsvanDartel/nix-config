# Turn eval warnings (deprecations, etc.) into hard errors, keeping the config
# warning-clean. Lands in the generated flake.nix's nixConfig (flake-file).
{...}: {
  flake-file.nixConfig.abort-on-warn = true;
}
