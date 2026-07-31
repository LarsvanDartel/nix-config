# Declarative noctalia plugins.
#
# Upstream's model is imperative: the shell git-clones a plugin into
# ~/.config/noctalia/plugins/<id> and records `enabled` in plugins.json. Two
# things stop us replacing that with a plain store symlink:
#
#   * a plugin's own settings live at <pluginDir>/settings.json, written by the
#     shell at runtime — a read-only store path makes saving fail silently;
#   * plugins.json also holds plugins you install by hand, which nix must not
#     clobber.
#
# So the plugin trees are *copied* out of pinned sources on activation (any
# existing settings.json preserved) and plugins.json is merged with jq rather
# than overwritten. Nix owns which plugins exist and that they are on; the shell
# keeps owning their settings and anything installed through the UI.
#
# Bar placement is a separate matter: `bar.widgets` lives in the store-owned
# settings.json, so a plugin's bar widget must be declared in ./home.nix as
# `plugin:<id>` — it cannot be dragged in from the settings panel.
{}: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkOption;
  inherit (lib.types) attrsOf raw submodule str path;

  cfg = config.cosmos.desktops.noctalia.plugins;

  mainSourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";

  # The official monorepo. Pinned: plugins are QML loaded straight into the
  # shell, so "whatever main happens to be today" is not a thing to auto-track.
  monorepo = pkgs.fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia-plugins";
    rev = "ea21cb63d063075bc0acd72d8b946ce2c5eef00d";
    hash = "sha256-M+7SLW+wI3KvDMj8dSrW/uUmpPiYhsXA2jpbbgL5imk=";
  };

  official = id: {
    src = "${monorepo}/${id}";
    sourceUrl = mainSourceUrl;
  };

  statesJson = builtins.toJSON (
    lib.mapAttrs (_: p: {
      enabled = true;
      inherit (p) sourceUrl;
    })
    cfg.installed
  );

  sourcesJson = builtins.toJSON (
    map (url: {
      inherit url;
      name =
        if url == mainSourceUrl
        then "Noctalia Plugins"
        else baseNameOf url;
      enabled = true;
    })
    (lib.unique (lib.mapAttrsToList (_: p: p.sourceUrl) cfg.installed))
  );

  # Named apart from `pkgs.jq` so `with pkgs` below still resolves the package.
  jqBin = lib.getExe pkgs.jq;
in {
  options.cosmos.desktops.noctalia.plugins.installed = mkOption {
    type = attrsOf (submodule {
      options = {
        src = mkOption {
          type = path;
          description = "Directory holding the plugin's manifest.json and QML.";
        };
        sourceUrl = mkOption {
          type = str;
          description = ''
            Repository the plugin came from. Recorded in plugins.json so the
            plugin manager can check it for updates.
          '';
        };
        settings = mkOption {
          type = attrsOf raw;
          default = {};
          description = ''
            Plugin settings, merged into ~/.config/noctalia/plugins/<id>/
            settings.json with these winning. Merged rather than written whole,
            so a value set in the plugin's own panel survives unless nix has an
            opinion about that same key.

            Only worth using for settings that have to hold: a plugin whose bar
            widget is too wide by default, say. Everything else is better left
            to the panel, which is still writable.
          '';
        };
      };
    });
    description = "Plugins installed into ~/.config/noctalia/plugins and enabled.";
    default = {
      # -- ThinkPad / power ---------------------------------------------------
      # Charge start/stop thresholds. Needs the udev rule + battery_ctl group
      # from hardware.thinkpad, or the sysfs write is denied.
      battery-threshold = official "battery-threshold";
      # Fan profiles and temperatures. Needs thinkpad_acpi fan_control=1 and a
      # writable /proc/acpi/ibm/fan — also hardware.thinkpad.
      thinkpad-fan = official "thinkpad-fan";
      # Power draw, time remaining, battery health. Reads UPower (desktop.power).
      battery-monitor-plus = official "battery-monitor-plus";

      # -- niri ---------------------------------------------------------------
      # Under Hyprland this asks the compositor (`hyprctl binds -j`); under niri
      # it parses ~/.config/niri/config.kdl as a file, which the wrapped config
      # would otherwise never create — see _niri/home.nix.
      keybind-cheatsheet = official "keybind-cheatsheet";
      display-settings = official "display-settings";
      niri-workspaces = official "niri-workspaces";
      niri-overview-launcher = official "niri-overview-launcher";

      # -- integrations -------------------------------------------------------
      protonvpn = official "protonvpn";
      # Mesh status, peer list and up/down. Shells out to the `netbird` CLI,
      # which services.netbird already puts on PATH, and reads the daemon over
      # its socket — which the client module leaves readable unprivileged, so
      # the widget works without a polkit prompt.
      netbird =
        official "netbird"
        // {
          # The widget puts the full NetBird address on the bar by default,
          # which is fifteen characters next to a right side that already
          # carries four permanently-shown readings — enough to push the bar
          # past its width. Off, both text fields are hidden and it draws as
          # the icon alone, the same as every other status widget up there.
          settings.showIpAddress = false;
        };
      ssh-sessions = official "ssh-sessions";
      model-usage = official "model-usage";
      # Not in the monorepo — its own repo, so its own pin.
      kde-connect = {
        src = pkgs.fetchFromGitHub {
          owner = "WerWolv";
          repo = "noctalia-kde-connect";
          rev = "1f2d257029a2031262898c78c242490205d15fe6";
          hash = "sha256-mbTISmEru887aMPAEDKCmSk/W+Wmfx8eWBltE7lp60g=";
        };
        sourceUrl = "https://github.com/WerWolv/noctalia-kde-connect";
      };

      # -- shell --------------------------------------------------------------
      plugin-manager = official "plugin-manager";
      # Replaces the standalone hyprpolkitagent unit (see _niri/system.nix):
      # only one process may own the polkit agent registration.
      polkit-agent = official "polkit-agent";
      privacy-indicator = official "privacy-indicator";
      screen-toolkit = official "screen-toolkit";
    };
  };

  config = {
    # The kde-connect plugin is a bar widget over the same D-Bus daemon, so
    # kdeconnect-indicator would only put a duplicate icon in the tray. mkForce
    # because home.kde-connect enables it outright — and it should stay enabled
    # there, since the Hyprland side has no such plugin and the tray icon is its
    # only way in.
    services.kdeconnect.indicator = lib.mkForce false;

    # …but the indicator's menu was also the only route to the KDE Connect GUI,
    # because home.kde-connect replaces the packaged launcher entry with a
    # hidden, `Exec=`-less stub. With no indicator here, that leaves no way to
    # reach per-device plugin configuration at all, so restore a working entry.
    # The plugin's own panel covers pairing and the common actions; this is for
    # everything past that.
    xdg.desktopEntries."org.kde.kdeconnect.app" = {
      exec = lib.mkForce "kdeconnect-app";
      icon = lib.mkForce "kdeconnect";
      categories = lib.mkForce ["Qt" "KDE" "Network"];
      settings.NoDisplay = lib.mkForce "false";
    };

    # Runtime dependencies the plugins shell out to. niri and hyprctl come from
    # the compositor's own session PATH.
    home.packages = with pkgs; [
      jq
      wlr-randr # display-settings
      # screen-toolkit: capture, OCR, QR, annotate, record
      grim
      slurp
      wl-clipboard
      tesseract
      imagemagick
      zbar
      curl
      translate-shell
      ffmpeg
      wl-screenrec
      gifski
      kdePackages.kdeconnect-kde # kde-connect plugin talks to kdeconnect-cli
    ];

    home.activation.noctaliaPlugins = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _pdir=${lib.escapeShellArg "${config.xdg.configHome}/noctalia/plugins"}
      run mkdir -p "$_pdir"

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (id: p: ''
          # Staged then swapped, so a failed copy never leaves a half-written
          # plugin the shell would try to load.
          run rm -rf "$_pdir/${id}.tmp"
          run cp -rT ${p.src} "$_pdir/${id}.tmp"
          run chmod -R u+w "$_pdir/${id}.tmp"
          if [ -f "$_pdir/${id}/settings.json" ]; then
            run cp "$_pdir/${id}/settings.json" "$_pdir/${id}.tmp/settings.json"
          fi
          ${lib.optionalString (p.settings != {}) ''
            run ${jqBin} -n --argjson nix ${lib.escapeShellArg (builtins.toJSON p.settings)} \
              --slurpfile old <(cat "$_pdir/${id}.tmp/settings.json" 2>/dev/null || echo '{}') \
              '($old[0] // {}) * $nix' > "$_pdir/${id}.tmp/settings.json.new" \
              && run mv "$_pdir/${id}.tmp/settings.json.new" "$_pdir/${id}.tmp/settings.json"
          ''}
          run rm -rf "$_pdir/${id}"
          run mv "$_pdir/${id}.tmp" "$_pdir/${id}"
        '')
        cfg.installed)}

      # Merge, never replace: `*` is jq's recursive object merge, and putting
      # the nix states on the right makes them win for managed plugins while
      # leaving hand-installed entries untouched.
      _pfile=${lib.escapeShellArg "${config.xdg.configHome}/noctalia/plugins.json"}
      _states=${lib.escapeShellArg statesJson}
      _sources=${lib.escapeShellArg sourcesJson}
      if [ -f "$_pfile" ]; then
        run ${jqBin} --argjson s "$_states" --argjson src "$_sources" \
          '.version = 2
           | .states = ((.states // {}) * $s)
           | .sources = (((.sources // []) + $src) | unique_by(.url))' \
          "$_pfile" > "$_pfile.tmp" && run mv "$_pfile.tmp" "$_pfile"
      else
        run ${jqBin} -n --argjson s "$_states" --argjson src "$_sources" \
          '{version: 2, states: $s, sources: $src}' > "$_pfile"
      fi
    '';
  };
}
