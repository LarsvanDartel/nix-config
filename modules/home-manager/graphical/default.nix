{lib, ...}: {
  imports = [
    ./hyprland
    ./mako
    ./waybar
    ./rofi
  ];

  options.modules.graphical = {
    startupCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Commands to run on startup";
    };
    commands = {
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
      passwordManager = lib.mkOption {
        type = lib.types.str;
        description = "Command to open password manager menu";
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
  };
}
