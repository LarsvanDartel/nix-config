# home.zen — the Zen browser, replacing the firefox aspect this was written
# from. Zen is a Firefox fork and its Home Manager module is home-manager's own
# mkFirefoxModule pointed at a different profile directory, so the policies and
# profile schema below carried over from firefox unchanged.
{...}: {
  flake-file.inputs.zen-browser = {
    url = "github:0xc000022070/zen-browser-flake";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      # Load-bearing. homeModules.beta imports mkFirefoxModule out of whichever
      # home-manager this input resolves to, so leaving it unpinned would
      # evaluate one home-manager's module schema inside a config built by
      # another.
      home-manager.follows = "home-manager";
    };
  };

  den.aspects.home.zen.homeManager = {
    inputs,
    pkgs,
    ...
  }: {
    # Twilight is Zen's nightly channel. Deliberately the flake's own twilight
    # rather than twilight-official: upstream publishes nightlies to a *rolling*
    # tag (zen-browser/desktop releases/download/twilight-1/...) that it
    # overwrites in place, so the pinned hash goes stale and the fetch dies on a
    # hash mismatch whenever a new nightly lands. The flake mirrors each
    # snapshot to an immutable timestamped tag instead, so the URL stays valid
    # and `nix flake update` is what moves the version. Same failure mode as the
    # discord pin documented in roles/desktop-home.nix.
    imports = [inputs.zen-browser.homeModules.twilight];

    # ~/.config/zen, not the ~/.config/mozilla firefox used — the module sets
    # both vendorPath and configPath to xdg.configHome/zen. Nothing migrates
    # the old profile across, so history and logins start empty.
    cosmos.system.impermanence.persist.directories = [".config/zen"];

    programs.zen-browser = {
      enable = true;

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

    # Not optional under abort-on-warn: stylix's zen-browser target warns when
    # profileNames is empty and programs.zen-browser is on, and a warning is a
    # hard eval failure here.
    stylix.targets.zen-browser.profileNames = ["default"];
  };
}
