# roles.desktop-home — the desktop home environment for the primary user on
# desktop hosts (was the homeManager `desktop` aggregate).
{den, ...}: {
  den.aspects.roles.desktop-home = {
    includes = with den.aspects.home; [
      styling
      wallpapers
      hyprland
      foot
      firefox
      mpv
      spotify
      # discord — disabled, not deleted. Its package fetches `full.distro`
      # from a version-pinned stable.dl2.discordapp.net URL that Discord
      # deletes when it ships the next build, so any machine without that
      # path already in its store cannot build this closure at all. It ran
      # here only because voyager fetched it while the URL still worked; CI
      # in a clean guest went red on it. The aspect and its persist entry are
      # untouched — re-add this line once nixpkgs points at a live URL.
      signal
      kde-connect
      bluetuith
      pulsemixer
      calculator
    ];

    # profile value: nvim in wayland mode on desktop.
    homeManager = {...}: {
      cosmos.cli.programs.nvim.wayland = true;
    };
  };
}
