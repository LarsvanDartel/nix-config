# Declarative noctalia plugins. Copied (not symlinked) on activation: plugins
# write their own settings.json at runtime, and plugins.json is jq-merged so
# hand-installed plugins aren't clobbered.
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

  # Pinned: plugins are QML loaded straight into the shell.
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
      # Needs the udev rule + battery_ctl group from hardware.thinkpad.
      battery-threshold = official "battery-threshold";
      # Needs thinkpad_acpi fan_control=1 (hardware.thinkpad).
      thinkpad-fan = official "thinkpad-fan";
      battery-monitor-plus = official "battery-monitor-plus";

      # -- niri ---------------------------------------------------------------
      # Under niri this parses ~/.config/niri/config.kdl — see _niri/home.nix.
      keybind-cheatsheet = official "keybind-cheatsheet";
      display-settings = official "display-settings";
      niri-workspaces = official "niri-workspaces";
      niri-overview-launcher = official "niri-overview-launcher";

      # -- integrations -------------------------------------------------------
      protonvpn = official "protonvpn";
      netbird =
        official "netbird"
        // {
          # Too wide on the bar next to the other readings.
          settings.showIpAddress = false;
        };
      ssh-sessions = official "ssh-sessions";
      model-usage = official "model-usage";
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
      # Replaces hyprpolkitagent (see _niri/system.nix): only one polkit agent
      # may register.
      polkit-agent = official "polkit-agent";
      privacy-indicator = official "privacy-indicator";
      screen-toolkit = official "screen-toolkit";
    };
  };

  config = {
    # Duplicates the kde-connect bar widget. mkForce: home.kde-connect must keep
    # it enabled for Hyprland, where the tray icon is the only way in.
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
