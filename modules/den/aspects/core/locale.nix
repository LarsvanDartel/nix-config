# core.locale aspect — timezone, locale, console, keymap (was
# flake.modules.nixos.common in modules/nixos/system/locale.nix).
{...}: {
  den.aspects.core.locale.nixos = {...}: {
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
      earlySetup = true;
      useXkbConfig = true;
    };

    services.xserver.xkb = {
      layout = "us";
      variant = "dvp";
      options = "caps:escape";
    };
  };
}
