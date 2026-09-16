# home.zen — the Zen browser, replacing the firefox aspect this was written
# from. A Firefox fork on home-manager's own mkFirefoxModule, so the policies
# and profile schema below carried over unchanged.
{...}: {
  flake-file.inputs.zen-browser = {
    url = "github:0xc000022070/zen-browser-flake";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      # Load-bearing: homeModules.beta imports mkFirefoxModule from whichever
      # home-manager this input resolves to — unpinned, one home-manager's
      # module schema would evaluate inside a config built by another.
      home-manager.follows = "home-manager";
    };
  };

  den.aspects.home.zen.homeManager = {
    inputs,
    pkgs,
    ...
  }: {
    # Twilight (Zen's nightly) via the flake's own input, not
    # twilight-official: upstream's rolling tag is overwritten in place, so a
    # pinned hash dies on mismatch at every new nightly. The flake mirrors to
    # immutable timestamped tags; `nix flake update` moves the version. Same
    # failure mode as the discord pin in roles/desktop-home.nix.
    imports = [inputs.zen-browser.homeModules.twilight];

    # ~/.config/zen (the module sets both vendorPath and configPath to it),
    # not firefox's ~/.config/mozilla — nothing migrates the old profile
    # across; history and logins start empty.
    cosmos.system.impermanence.persist.directories = [".config/zen"];

    # Firefox resolves native messaging hosts via ~/.mozilla/native-messaging-hosts
    # regardless of where the profile lives — Zen keeps its profile in
    # ~/.config/zen but looks here.
    #
    # Linked by hand, not `mozilla.firefoxNativeMessagingHosts`: that option
    # links the whole directory with ignorelinks = true, putting each manifest
    # symlink straight into the host package's store path. checkLinkTargets
    # then reads the previous generation's symlink as unmanaged and activation
    # aborts with "would be clobbered" on every rebuild touching the host.
    # Linking the manifest ourselves keeps it inside home-manager-files, where
    # home-manager can replace it.
    #
    # force: that migration left survivors — a mid-session switch finds files
    # the running generation put in unpersisted ~/.mozilla, and anything not
    # resolving under home-manager-files aborts all of activation. The
    # manifest is generated and holds nothing user-written; not worth failing
    # a rebuild over.
    home.file.".mozilla/native-messaging-hosts/webbluetooth_host.json" = {
      source = "${pkgs.web-bluetooth-firefox-host}/lib/mozilla/native-messaging-hosts/webbluetooth_host.json";
      force = true;
    };

    # setAsDefaultBrowser writes defaultApplications but does not enable the
    # module itself; without this it works only by accident, via whichever
    # other aspect switched it on.
    xdg.mimeApps.enable = true;

    programs.zen-browser = {
      enable = true;

      # Web Bluetooth: Firefox never implemented it, so BLE from a page (the
      # smart cube on cstimer.net) works in Chrome and nowhere else. This host
      # provides navigator.bluetooth over stdio via BlueZ/bleak; the extension
      # below is the other half, useless without it. The manifest's
      # allowed_extensions names only that extension, so nothing else can reach
      # the Bluetooth stack.
      #
      # Not sufficient alone — hence the manifest link above: this option only
      # feeds the host into the package wrapper, and Zen looks it up at runtime
      # in ~/.mozilla, where nothing had put it.
      nativeMessagingHosts = [pkgs.web-bluetooth-firefox-host];

      # Claims http/https, html/xhtml, and BROWSER. Everything it writes is
      # mkDefault, so an aspect wanting a type back just states it — how
      # thunderbird keeps mailto below.
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
            proton-pass
            zotero-connector
          ])
          ++ [
            # Page half of Web Bluetooth, paired with the native host above.
            # Installed here, not via ExtensionSettings policy: install_url is
            # only consulted when the id is absent, so with a copy already in
            # the profile the policy did nothing. This symlinks the xpi in and
            # replaces what is there. Own build, not AMO's —
            # pkgs/web-bluetooth-firefox.nix has the fix it carries.
            pkgs.web-bluetooth-firefox-extension
          ];

        settings = {
          "browser.tabs.inTitlebar" = 0;
          "extensions.autoDisableScopes" = 0;

          # The web bluetooth extension is an unsigned own build (fix upstream
          # hasn't shipped), so Zen disables it as unverifiable; the build
          # permits this pref off but something sets it back, so state it.
          # Costs little: every other add-on here is a signed AMO build via
          # the nix store — this check guards browse-to-install, which is not
          # how anything enters this profile.
          "xpinstall.signatures.required" = false;
          "devtools.chrome.enabled" = true;
          "devtools.debugger.remote-enabled" = true;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "network.trr.mode" = 5;
        };

        search.force = true;
        containersForce = true;
      };
    };

    # Required under abort-on-warn: stylix warns when profileNames is empty
    # with zen-browser on, and a warning is a hard eval failure.
    stylix.targets.zen-browser.profileNames = ["default"];
  };
}
