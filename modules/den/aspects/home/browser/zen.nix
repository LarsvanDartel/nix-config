# home.zen — the Zen browser (Firefox fork on home-manager's mkFirefoxModule)
{...}: {
  flake-file.inputs.zen-browser = {
    url = "github:0xc000022070/zen-browser-flake";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      # Load-bearing: homeModules imports mkFirefoxModule from this input's
      # home-manager; unpinned, two module schemas would mix.
      home-manager.follows = "home-manager";
    };
  };

  den.aspects.home.zen.homeManager = {
    inputs,
    lib,
    pkgs,
    ...
  }: {
    # Not twilight-official: upstream's rolling tag is overwritten in place, so
    # a pinned hash breaks at every nightly. The flake mirrors to immutable tags.
    imports = [inputs.zen-browser.homeModules.twilight];

    cosmos.system.impermanence.persist.directories = [".config/zen"];

    # Linked by hand into ~/.mozilla, where Zen looks: firefoxNativeMessagingHosts' ignorelinks
    # abort activation ("would be clobbered"). force clears leftover unmanaged files.
    home.file.".mozilla/native-messaging-hosts/webbluetooth_host.json" = {
      source = "${pkgs.web-bluetooth-firefox-host}/lib/mozilla/native-messaging-hosts/webbluetooth_host.json";
      force = true;
    };

    # setAsDefaultBrowser does not enable the module itself.
    xdg.mimeApps.enable = true;

    programs.zen-browser = {
      enable = true;

      # Web Bluetooth host for the extension below; Zen only finds it via the ~/.mozilla link above.
      nativeMessagingHosts = [pkgs.web-bluetooth-firefox-host];

      # Everything it writes is mkDefault — thunderbird reclaims mailto.
      setAsDefaultBrowser = true;

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
        # Any policies.json engages the policy engine, which blocks Web Serial (ESP flashing); 3 = allow.
        DefaultSerialGuardSetting = 3;
        PasswordManagerEnabled = false;
        TranslateEnabled = true;
        UseSystemPrintDialog = true;
      };

      profiles.default = {
        id = 0;
        name = "default";
        isDefault = true;

        search.default = "ddg";

        extensions.packages =
          (with pkgs.nur.repos.rycee.firefox-addons; [
            ublock-origin
            bitwarden
            zotero-connector
            privacy-pass
          ])
          ++ [
            # Not via ExtensionSettings policy: install_url is ignored once the id
            # is in the profile. Own build — see pkgs/web-bluetooth-firefox.nix.
            pkgs.web-bluetooth-firefox-extension
          ];

        settings = {
          "browser.tabs.inTitlebar" = 0;
          "extensions.autoDisableScopes" = 0;

          # The web bluetooth extension is an unsigned own build; something
          # resets this pref, so state it. All other add-ons arrive via nix.
          "xpinstall.signatures.required" = false;
          "devtools.chrome.enabled" = true;
          "devtools.debugger.remote-enabled" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "network.trr.mode" = 5;

          # Not stylix's pixel font: pages size code text themselves (GitHub's 12px…),
          # and Gecko ignores the fontconfig rule that keeps it on its pixel grid.
          "font.name.monospace.x-western" = lib.mkForce "DejaVu Sans Mono";

          # Follow the desktop's light/dark preference live (`theme`), not
          # stylix's fixed polarity; its chrome CSS follows on restart.
          "zen.view.window.scheme" = lib.mkForce 2;
        };

        search.force = true;
        containersForce = true;
      };
    };

    # Required under abort-on-warn: stylix warns when profileNames is empty.
    stylix.targets.zen-browser.profileNames = ["default"];
  };
}
