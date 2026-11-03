# core.locale — timezone, locale, console, keymap.
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
        # English names, ISO dates (2026-11-03), weeks start on Monday, in both
        # glibc and CLDR; en_DK has ISO dates only in glibc.
        LC_TIME = "en_SE.UTF-8";
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
