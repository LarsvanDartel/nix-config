# Declarative noctalia plugins: read-only `path` sources from the store, never
# cloned or auto-updated.
{inputs}: {
  config,
  lib,
  pkgs,
  ...
}: let
  # Pinned: plugins are trusted Luau loaded straight into the shell.
  community = pkgs.applyPatches {
    name = "noctalia-community-plugins";
    src = pkgs.fetchFromGitHub {
      owner = "noctalia-dev";
      repo = "community-plugins";
      rev = "e9dec7443b8a70ab606dc72669fb122a9d668bce";
      hash = "sha256-n1uQOXXjIrPvDe5dXPpcCefNsQVAoEo5lVDkOPy81vU=";
    };
    # The fan's RPM is the only bold bar label; Cozette has no bold cut in the same
    # family, so it renders synthesized. --replace-fail flags an upstream change.
    postPatch = ''
      substituteInPlace thinkpad-fan/widget.luau --replace-fail 'fontWeight = "bold",' ""
    '';
  };

  # Bitwarden search over rbw, which already holds the vault.lvdar.nl session.
  # Written before plugin_api existed, and with the `/` its prefix must not carry. Its
  # catalog.toml lacks plugin_api too; without one, a path source is scanned instead.
  vinnyduke = pkgs.applyPatches {
    name = "noctalia-v5-plugins-vinnyduke";
    src = pkgs.fetchFromGitHub {
      owner = "vinnyduke";
      repo = "noctalia-v5-plugins";
      rev = "7eeaa3a98eac93e7b48508fc55fadae8e38622c7";
      hash = "sha256-Ia46mksJ9PQ47fZq2GeKFXOhDfnS4UVaabM+GUbpiP0=";
    };
    postPatch = ''
      substituteInPlace rbw-launcher/plugin.toml \
        --replace-fail 'min_noctalia = "5.0.0"' 'plugin_api = 3' \
        --replace-fail 'prefix = "/rbw"' 'prefix = "rbw"'
      rm catalog.toml
    '';
  };
in {
  programs.noctalia.settings = {
    plugins = {
      auto_update = "none";
      # Declaring sources drops the default official/community git sources.
      source = [
        {
          name = "community-pinned";
          kind = "path";
          location = "${community}";
          enabled = true;
        }
        {
          name = "lvdar";
          kind = "path";
          location = "${inputs.noctalia-netbird}";
          enabled = true;
        }
        {
          name = "vinnyduke";
          kind = "path";
          location = "${vinnyduke}";
          enabled = true;
        }
      ];
      enabled = [
        "damian-ds7/battery-threshold" # needs hardware.thinkpad's battery_ctl udev rule
        "piero-93/thinkpad-fan" # needs thinkpad_acpi fan_control=1 (hardware.thinkpad)
        "kenn/keybind-cheatsheet" # parses ~/.config/niri/config.kdl (_niri/home.nix)
        "raycursive/niri-displays"
        "icefish/phone-connect"
        "alexander/screen-toolkit"
        "lvdar/netbird"
        "vinnyduke/rbw-launcher" # launcher prefix /rbw
      ];
    };
    plugin_settings."lvdar/netbird" = {
      instance_labels = {
        netbird = "lvdar";
        netbird-gewis = "gewis";
      };
      # The palette has no green role; base16's green is the theme's.
      connected_color = config.lib.stylix.colors.withHashtag.base0B;
    };
  };

  # phone-connect's bar widget replaces the tray indicator. mkForce: home.kde-connect
  # must keep it enabled for Hyprland, where the tray icon is the only way in.
  services.kdeconnect.indicator = lib.mkForce false;

  # home.kde-connect hides the launcher entry; restore it for per-device config.
  xdg.desktopEntries."org.kde.kdeconnect.app" = {
    exec = lib.mkForce "kdeconnect-app";
    icon = lib.mkForce "kdeconnect";
    categories = lib.mkForce ["Qt" "KDE" "Network"];
    settings.NoDisplay = lib.mkForce "false";
  };

  # niri and hyprctl come from the compositor's session PATH.
  home.packages = with pkgs; [
    # screen-toolkit
    slurp
    hyprpicker
    tesseract
    imagemagick
    zbar
    curl
    jq
    translate-shell
    ffmpeg
    wl-screenrec
    wl-clipboard
    # phone-connect
    kdePackages.kdeconnect-kde
    sshfs
    glib
  ];
}
