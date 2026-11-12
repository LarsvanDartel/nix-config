# Declarative noctalia plugins: read-only `path` sources from the store, never
# cloned or auto-updated.
{inputs}: {pkgs, ...}: let
  # Pinned: plugins are trusted Luau loaded straight into the shell.
  # phone-connect's bar labels hardcode 10/11px; without a fontSize a plugin
  # label gets the body size every built-in bar widget uses.
  community = pkgs.applyPatches {
    name = "noctalia-community-plugins";
    src = pkgs.fetchFromGitHub {
      owner = "noctalia-dev";
      repo = "community-plugins";
      rev = "e9dec7443b8a70ab606dc72669fb122a9d668bce";
      hash = "sha256-n1uQOXXjIrPvDe5dXPpcCefNsQVAoEo5lVDkOPy81vU=";
    };
    postPatch = ''
      substituteInPlace phone-connect/widget.luau \
        --replace-fail 'fontSize = 10,' "" \
        --replace-fail 'fontSize = 11,' ""
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
        "damian-ds7/battery-threshold" # needs desktop.power's battery_ctl udev rule
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
      # A palette role, so it follows `theme`: a hex here would stay the default
      # mode's (.config/noctalia/ is outside the farm). There is no green role;
      # tertiary is base0C, the theme's aqua.
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
