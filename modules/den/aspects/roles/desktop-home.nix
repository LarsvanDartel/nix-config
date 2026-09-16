# roles.desktop-home — the desktop home environment for the primary user on
# desktop hosts.
{den, ...}: {
  den.aspects.roles.desktop-home = {
    includes = with den.aspects.home; [
      styling
      wallpapers
      hyprland
      foot
      # `, <cmd>` + command-not-found suggestions. Here, not home-base: the
      # prebuilt index is 101 MB and pioneer has no room for it — see the aspect.
      comma
      zen
      mpv
      spotify
      # Pinned to a stable.dl2.discordapp.net URL that Discord deletes when
      # it ships the next build, so only a machine with that path already in
      # its store can build this closure (voyager can; a fresh install or a
      # store GC breaks it). voyager's problem alone since the CI gate went.
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
