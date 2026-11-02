# Theming

One base16 theme, in a dark and a light mode, switched at runtime without a rebuild. The theme is Everforest: `everforest` (dark) and `everforest-light-medium` (light) from tinted-theming, with the Everforest icon theme.

## Switching

- `theme` prints the mode; `theme dark`, `theme light` and `theme toggle` switch it.
- noctalia's own light/dark controls (control-center shortcut, `noctalia msg theme-mode-toggle`) do the same: its `theme_mode_changed` hook runs `theme sync`, and `theme` tells noctalia in turn.
- The mode survives reboots and rebuilds: it is the link `~/.local/state/cosmos/theme/current` (persisted), and every activation keeps it and points noctalia's `settings.toml` at it.
- It works the same under niri and Umbriel: the switch is per session, not per compositor.

| When it repaints | What |
|---|---|
| Live | noctalia (bar, panels, launcher, OSD, lock screen), niri and Umbriel borders, foot (`SIGUSR1`/`SIGUSR2`), tmux (`source-file`), btop (`SIGUSR2`), GTK3 apps (`gtk-theme` flips adw-gtk3/adw-gtk3-dark), GTK4/libadwaita apps and zen (portal `color-scheme`), icons |
| Next launch | Everforest tints in GTK3/GTK4 (`gtk.css`), Qt (qtct/Kvantum), zen's chrome CSS, yazi, zathura, nvim, bat, lazygit, mpv, spotify-player |
| Never (default mode) | greeter, plymouth, console, GRUB: system-level, before any session |

## Changing theme or default mode

`modules/den/aspects/desktop/styling.nix`: `themes` lists each theme's dark and light scheme and icon theme, `theme` picks one, `defaultMode` is what the system and a fresh home start in.

## How it works

- `cosmosStyling` (`desktop/styling.nix`) holds both schemes: `schemeFile mode`, `colors pkgs mode`, `modes`, `defaultMode`.
- stylix renders the default mode as usual (`home.styling`). `home.theme` (`home/desktop/theme.nix`) evaluates the home twice more with `extendModules`, once per mode with switching off, and compares every home file: whatever differs (GTK CSS and settings, Qt, btop, bat, zen CSS…) moves into a per-mode link farm and becomes an out-of-store link through `current`. New stylix targets are picked up without listing them.
- Wrapped programs (foot, tmux, yazi, zathura, nvim) are built once per mode by `cosmosStyling.modal`, whose `bin/` entries exec the variant `current` names.
- Extra per-mode files and repaint steps come from `cosmos.desktops.common.styling.modes` (`home.theme-options`, declared in every home): `files.<name> = mode: …` lands in the farm (niri's `niri.kdl` and Umbriel's `umbriel.toml` colours, tmux's colours), `onSwitch` runs after a switch with `$mode` and `$farm`, `exclude` keeps paths out of the farm (noctalia carries both palettes itself; systemd units can't switch).
- niri includes `~/.local/state/cosmos/theme/current/niri.kdl` last (`include optional=true`, watched); Umbriel includes `umbriel.toml` (`[include.optional]`) and gets `umbriel msg config-reload`.

## Adding a themed program

1. A stylix target needs nothing: its files are detected.
2. A wrapped program takes the mode: `mk<prog> = pkgs: mode: …` with `cosmosStyling.colors pkgs mode`, installed via `cosmosStyling.modal`.
3. A program that can repaint while running adds an `onSwitch` line that does not fail when it isn't running.

## Pitfalls

- stylix's gnome and kde targets are off: on niri they only rewrote dconf's `color-scheme` at every activation, undoing the mode.
- A file whose *name* differs per mode can't be switched by a link; the build asserts against it.
- `theme` fails with "missing" until the first activation that has `home.theme` created the farms.
