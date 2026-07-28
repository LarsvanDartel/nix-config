# home.firefox
{...}: {
  den.aspects.home.firefox.homeManager = {
    config,
    pkgs,
    ...
  }: {
    cosmos.system.impermanence.persist.directories = [".config/mozilla"];

    programs.firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";

      policies = {
        AppAutoUpdate = false;
        BlockAboutAddons = false;
        BlockAboutConfig = false;
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

        search.default = "ddg";

        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          ublock-origin
          proton-pass
          zotero-connector
        ];

        settings = {
          "browser.tabs.inTitlebar" = 0;
          "extensions.autoDisableScopes" = 0;
          "devtools.chrome.enabled" = true;
          "devtools.debugger.remote-enabled" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "network.trr.mode" = 5;
        };

        search.force = true;
        containersForce = true;
      };
    };
    stylix.targets.firefox.profileNames = ["default"];
  };
}
