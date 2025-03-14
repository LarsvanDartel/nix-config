{lib, ...}: {
  imports = [
    ./alacritty
    ./foot
  ];

  options.modules.terminal = {
    default = lib.mkOption {
      type = lib.types.str;
      default = "foot";
      description = "Default terminal application";
    };
  };
}
