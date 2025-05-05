{
  time.timeZone = "Europe/Amsterdam";
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocales = [
      "nl_NL.UTF-8"
    ];
    extraLocaleSettings = {
      LC_NUMERIC = "C.UTF-8";
      LC_TIME = "nl_NL.UTF-8";
      LC_MONETARY = "nl_NL.UTF-8";
    };
  };
}
