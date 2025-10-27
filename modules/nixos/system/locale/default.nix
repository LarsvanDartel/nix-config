{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.system.locale;
in {
  options.cosmos.system.locale = {
    enable = mkEnableOption "locale configuration";
  };

  config = mkIf cfg.enable {
    time.timeZone = "Europe/Amsterdam";
    i18n = {
      defaultLocale = "en_US.UTF-8";
      extraLocales = [
        "nl_NL.UTF-8/UTF-8"
      ];
      extraLocaleSettings = {
        LC_NUMERIC = "C.UTF-8";
        LC_TIME = "nl_NL.UTF-8";
        LC_MONETARY = "nl_NL.UTF-8";
      };
    };

    console = {
      earlySetup = true; # Switch keymap for Nixos stage 1
      useXkbConfig = true; # use xkb options in tty.
    };

    # Configure keymap in X11
    services.xserver.xkb = {
      layout = "us";
      variant = "dvp";
      options = "caps:escape";
    };
  };
}
