{lib, ...}: let
  inherit (lib.options) mkOption;
  inherit (lib.types) str attrsOf lines;
in {
  imports = [
    ./zsh
  ];

  options.modules.terminal.shell = {
    aliases = mkOption {
      type = attrsOf str;
      description = "shell aliases";
    };

    initContent = mkOption {
      type = lines;
      default = "";
      description = "shell init content";
    };
  };
}
