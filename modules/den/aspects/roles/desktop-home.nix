# roles.desktop-home — the desktop home environment for the primary user on
# desktop hosts (was the homeManager `desktop` aggregate).
{den, ...}: {
  den.aspects.roles.desktop-home = {
    includes = with den.aspects.home; [
      styling
      wallpapers
      hyprland
      foot
      zen
      mpv
      spotify
      # Fetches `full.distro` from a version-pinned stable.dl2.discordapp.net
      # URL that Discord deletes when it ships the next build, so a machine
      # without that path already in its store cannot build this closure —
      # voyager can only because it fetched it while the URL still worked. It
      # was dropped for a while because CI in a clean guest went red on it;
      # with that gate gone it is voyager's problem alone, and voyager has the
      # path. Expect it to bite on a fresh install or after a store GC.
      discord
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
