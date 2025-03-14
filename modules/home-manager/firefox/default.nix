{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.firefox;
in {
  options.modules.firefox = {
    enable = lib.mkEnableOption "firefox browser";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      ".mozilla"
    ];
    programs.firefox = {
      enable = true;

      policies = {
        AppAutoUpdate = false;
        BlockAboutAddons = true;
        BlockAboutConfig = true;
        BlockAboutProfiles = true;
        DisableAppUpdate = true;
        DisableFeedbackCommands = true;
        DisableMasterPasswordCreation = true;
        DisablePocket = true;
        DisableProfileImport = true;
        DisableSetDesktopBackground = true;
        DisableTelemetry = true;
        DisplayBookmarksToolbar = "never";
        DisplayMenuBar = "never";
        DNSOverHTTPS.Enabled = false;
        DontCheckDefaultBrowser = true;
        PasswordManagerEnabled = false;
        TranslateEnabled = true;
        UseSystemPrintDialog = true;
      };

      profiles.default = {
        id = 0;
        name = "default";
        isDefault = true;

        search.default = "DuckDuckGo";

        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          ublock-origin
        ];

        settings = {
          "browser.tabs.inTitlebar" = 0;
          "extensions.autoDisableScopes" = 0;
          "devtools.chrome.enabled" = true;
          "devtools.debugger.remote-enabled" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        };

        search.force = true;
        containersForce = true;
      };
    };
    stylix.targets.firefox.profileNames = ["default"];
  };
}
