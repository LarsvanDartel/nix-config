{lib, ...}: {
  imports = [
    ./hyprland
    ./waybar
    ./rofi
  ];

  options.modules.graphical.commands = {
    launcher = lib.mkOption {
      type = lib.types.str;
      description = "Command to open app launcher";
    };
    windowSwitch = lib.mkOption {
      type = lib.types.str;
      description = "Command to choose windows";
    };
    powerMenu = lib.mkOption {
      type = lib.types.str;
      description = "Command for power options menu";
    };
    toggleBar = lib.mkOption {
      type = lib.types.str;
      description = "Command to toggle status bar";
    };
    audioSwitch = lib.mkOption {
      type = lib.types.str;
      description = "Command to choose audio source";
    };
    brightness = lib.mkOption {
      type = lib.types.str;
      description = "Command for adjusting brightness";
    };
    calculator = lib.mkOption {
      type = lib.types.str;
      description = "Command for quick calculations";
    };
    emoji = lib.mkOption {
      type = lib.types.str;
      description = "Command for picking emoji";
    };
  };
}
