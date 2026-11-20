# home.noctalia — declarative noctalia plugins as read-only store `path` sources, never auto-updated.
{inputs}: {pkgs, ...}: let
  # Pinned: plugins are trusted Luau loaded straight into the shell.
  community = pkgs.applyPatches {
    name = "noctalia-community-plugins";
    src = pkgs.fetchFromGitHub {
      owner = "noctalia-dev";
      repo = "community-plugins";
      rev = "e9dec7443b8a70ab606dc72669fb122a9d668bce";
      hash = "sha256-n1uQOXXjIrPvDe5dXPpcCefNsQVAoEo5lVDkOPy81vU=";
    };
    # phone-connect hardcodes font and glyph sizes; unset, it matches the built-in bar widgets.
    # screen-toolkit reads [shell.screenshot] from settings.toml only; home-manager writes config.toml.
    postPatch = ''
      substituteInPlace phone-connect/widget.luau \
        --replace-fail 'fontSize = 10,' "" \
        --replace-fail 'fontSize = 11,' "" \
        --replace-fail 'size = 14, ' "" \
        --replace-fail 'size = 12, ' ""
      substituteInPlace screen-toolkit/scripts/shell-capture.sh \
        --replace-fail '"$HOME/.config/noctalia/settings.toml"; do' \
          '"$HOME/.config/noctalia/settings.toml" "$HOME/.config/noctalia/config.toml"; do'
    '';
  };

  # rbw-launcher predates plugin_api and its prefix must not carry the `/`. Its catalog.toml
  # lacks plugin_api too; without one, the path source is scanned instead.
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
        "damian-ds7/battery-threshold" # needs desktop.power's battery_ctl udev rule
        "kenn/keybind-cheatsheet" # parses ~/.config/niri/config.kdl (_niri/home.nix)
        "raycursive/niri-displays"
        "icefish/phone-connect"
        "alexander/screen-toolkit"
        "lvdar/netbird"
        "vinnyduke/rbw-launcher"
      ];
    };
    plugin_settings."lvdar/netbird" = {
      instance_labels = {
        netbird = "lvdar";
        netbird-gewis = "gewis";
      };
      # A palette role, not a hex (docs/src/theming.md#pitfalls); tertiary is base0C, the
      # theme's aqua, as there is no green role.
      connected_color = "tertiary";
    };
  };

  # niri comes from the compositor's session PATH.
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
