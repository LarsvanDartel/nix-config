{lib, ...}: let
  inherit (lib.options) mkOption;
  inherit (lib.types) str attrsOf;
in {
  imports = [
    ./prompt
    ./zsh
  ];

  options.modules.shell = {
    aliases = mkOption {
      type = attrsOf str;
      description = "shell aliases";
    };
  };
}
