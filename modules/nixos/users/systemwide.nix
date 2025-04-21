{
  config,
  lib,
  ...
}: let
  inherit (lib.attrsets) attrNames isAttrs recursiveUpdate;
  inherit (lib.filesystem) listFilesRecursive;
  inherit (lib.lists) any filter foldr;
  inherit (lib.modules) mkIf;

  moduleFiles =
    filter
    (file: baseNameOf file == "systemwide.nix" && (baseNameOf (dirOf file) != "users"))
    (listFilesRecursive ../..);

  moduleConfig = foldr (file: acc: recursiveUpdate acc (import file)) {} moduleFiles;

  moduleNames = attrNames moduleConfig;

  mkModule = name: moduleConfig: {pkgs, ...}: {
    config =
      mkIf
      (
        any
        (user: config.home-manager.users.${user}.systemwide.${name}.enable)
        (attrNames config.home-manager.users)
      )
      (
        if (isAttrs moduleConfig)
        then moduleConfig
        else (moduleConfig {inherit config pkgs;})
      );
  };
in {
  imports = map (name: mkModule name moduleConfig."${name}") moduleNames;
}
