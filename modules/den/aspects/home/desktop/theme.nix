# home.theme — light/dark switching at runtime, without a rebuild. Every file
# whose content depends on the mode is rendered for both modes and linked
# through ~/.local/state/cosmos/theme/current; `theme dark|light|toggle` flips
# that link and pokes running programs. See docs/src/theming.md.
{cosmosStyling, ...}: {
  den.aspects.home.theme.homeManager = {
    config,
    lib,
    pkgs,
    extendModules,
    ...
  }: let
    inherit (lib.modules) mkIf mkForce;
    inherit (cosmosStyling) modes defaultMode;

    cfg = config.cosmos.desktops.common.styling.modes;
    state = "${config.home.homeDirectory}/${cosmosStyling.stateDir}";

    # This home again in one mode, with the switching itself off. Only what
    # the farm reads gets evaluated.
    render = mode:
      (extendModules {
        modules = [
          {
            cosmos.desktops.common.styling.modes.enable = mkForce false;
            stylix.base16Scheme = mkForce (cosmosStyling.schemeFile mode);
            stylix.polarity = mkForce mode;
          }
        ];
      }).config;
    rendered = lib.genAttrs modes render;
    files = lib.mapAttrs (_: c: lib.filterAttrs (_: f: f.enable) c.home.file) rendered;

    excluded = target: lib.any (prefix: lib.hasPrefix prefix target) cfg.exclude;
    # Mode-dependent home files: what stylix (GTK, Qt, btop, bat, zen CSS…)
    # renders differently per mode.
    modal =
      lib.filterAttrs (
        name: f:
          !excluded f.target
          && lib.any (mode: "${(files.${mode}.${name} or f).source}" != "${f.source}") modes
      )
      files.${defaultMode};

    # A modal directory becomes one link, so home files inside it (Qt's
    # Kvantum/kvantum.kvconfig in Kvantum/) move into the farm with it.
    under = dir: target: lib.hasPrefix "${dir}/" target;
    linked = lib.filterAttrs (_: f: !lib.any (m: under m.target f.target) (lib.attrValues modal)) modal;
    nested = lib.filterAttrs (_: f: lib.any (m: under m.target f.target) (lib.attrValues linked)) files.${defaultMode};

    # Parents before children: a recursive directory is copied as links, so
    # its nested files can join it.
    farm = mode: let
      entries = lib.sortOn (f: lib.stringLength f.target) (lib.mapAttrsToList (name: _: files.${mode}.${name}) (linked // nested));
      list = pkgs.writeText "theme-${mode}-files" (lib.concatMapStrings (f: "${f.target}\t${f.source}\t${
          if f.recursive
          then "1"
          else "0"
        }\n")
        entries);
    in
      pkgs.runCommand "theme-${mode}" {} ''
        mkdir -p $out/home
        while IFS=$'\t' read -r target source recursive; do
          dest="$out/home/$target"
          mkdir -p "$(dirname "$dest")"
          if [ "$recursive" = 1 ] && [ -d "$source" ]; then
            mkdir -p "$dest"
            cp -rs --no-preserve=mode "$source"/. "$dest"/
          else
            ln -sfn "$source" "$dest"
          fi
        done < ${list}
        ${lib.concatStrings (lib.mapAttrsToList (name: mk: ''
            ln -s ${mk mode} "$out/"${lib.escapeShellArg name}
          '')
          cfg.files)}
      '';

    # The desktop-wide preference (portal color-scheme, read live by GTK4,
    # browsers and Electron) plus GTK3's theme and the icon theme, which
    # running GTK apps also pick up live.
    dconfFor = mode: let
      c = rendered.${mode};
    in {
      "/org/gnome/desktop/interface/color-scheme" = "prefer-${mode}";
      "/org/gnome/desktop/interface/gtk-theme" = c.gtk.theme.name;
      "/org/gnome/desktop/interface/icon-theme" = c.gtk.iconTheme.name;
    };
    dconfWrites = dconf: mode:
      lib.concatStrings (lib.mapAttrsToList (key: value: ''
          ${dconf} write ${key} ${lib.escapeShellArg "'${value}'"}
        '')
        (dconfFor mode));

    theme = pkgs.writeShellApplication {
      name = "theme";
      runtimeInputs = with pkgs; [coreutils procps dconf];
      text = ''
        state=${lib.escapeShellArg state}

        current() {
          readlink "$state/current" 2>/dev/null || echo ${defaultMode}
        }

        apply() {
          mode=$1
          case $mode in
          ${lib.concatStringsSep "|" modes}) ;;
          *)
            echo "theme: unknown mode '$mode'" >&2
            exit 2
            ;;
          esac
          if [ ! -e "$state/$mode" ]; then
            echo "theme: $state/$mode is missing; it appears with the next home-manager activation" >&2
            exit 1
          fi
          ln -sfn "$mode" "$state/.current"
          mv -T "$state/.current" "$state/current"
          # Read by the pokes below.
          farm="$state/$mode"
          export mode farm

          case $mode in
          ${lib.concatMapStrings (mode: ''
            ${mode})
            ${dconfWrites "dconf" mode}  ;;
          '')
          modes}esac

          ${cfg.onSwitch}
        }

        usage() {
          echo "usage: theme [${lib.concatStringsSep "|" modes}|toggle]" >&2
          exit 2
        }

        case ''${1:-} in
        "") current ;;
        toggle)
          if [ "$(current)" = dark ]; then apply light; else apply dark; fi
          ;;
        ${lib.concatStringsSep "|" modes}) apply "$1" ;;
        # From noctalia's theme_mode_changed hook: only when it differs, as
        # noctalia also echoes the mode `apply` just set.
        sync)
          [ $# -eq 2 ] || usage
          [ "$(current)" = "$2" ] || apply "$2"
          ;;
        *) usage ;;
        esac
      '';
    };
  in {
    config = lib.mkMerge [
      {
        cosmos.desktops.common.styling.modes = {
          enable = lib.mkDefault true;
          inherit rendered;
          package = theme;
        };
      }
      (mkIf cfg.enable {
        assertions = [
          {
            assertion = lib.all (mode: lib.attrNames files.${mode} == lib.attrNames files.${defaultMode}) modes;
            message = "home.theme: the light and dark renders have different home files; a mode-dependent file name cannot be switched by a link.";
          }
        ];

        home.packages = [theme];

        # Units name the files they restart on; a link can't switch a unit.
        cosmos.desktops.common.styling.modes.exclude = [".config/systemd/"];

        home.file =
          lib.mapAttrs (_: f: {
            source = mkForce (config.lib.file.mkOutOfStoreSymlink "${state}/current/home/${f.target}");
            recursive = mkForce false;
          })
          linked
          // lib.mapAttrs (_: _: {enable = mkForce false;}) nested;

        # After dconfSettings: home-manager rewrites gtk-theme/icon-theme for
        # the default mode on every activation (and so every boot).
        home.activation.theme = lib.hm.dag.entryAfter ["writeBoundary" "dconfSettings"] ''
          state=${lib.escapeShellArg state}
          run mkdir -p "$state"
          ${lib.concatMapStrings (mode: ''
              run ln -sfn ${farm mode} "$state/${mode}"
            '')
            modes}
          case "$(readlink "$state/current" 2>/dev/null)" in
          ${lib.concatStringsSep "|" modes}) ;;
          *) run ln -sfn ${defaultMode} "$state/current" ;;
          esac

          if [[ -v DBUS_SESSION_BUS_ADDRESS ]]; then
            dconf="${pkgs.dconf}/bin/dconf"
          else
            dconf="${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon ${pkgs.dconf}/bin/dconf"
          fi
          case "$(readlink "$state/current")" in
          ${lib.concatMapStrings (mode: ''
              ${mode})
              ${dconfWrites "run $dconf" mode}  ;;
            '')
            modes}esac
        '';

        cosmos.system.impermanence.persist.directories = [cosmosStyling.stateDir];
      })
    ];
  };
}
