# home.wallpapers — the background collection, recoloured to the active stylix
# palette and linked into a directory the wallpaper picker (noctalia's
# WallpaperSelector / control centre) browses.
#
# The images come from their own git repo on the knot (the `wallpapers` flake
# input, declared below) rather than being fetched one file at a time. They are binary, they change as
# a set, and the previous shape needed a URL and a hash per image — adding one
# meant editing nix, and there was nowhere to put a picture that was not also a
# nix expression.
#
# `theme.enable` will run them through imagemagick's `-remap` against a swatch
# strip built from the 16 base16 colours, with Floyd-Steinberg dithering, so a
# background uses *only* theme colours. It is off: a sixteen-colour remap is a
# heavy hand on a photograph, and the collection is photographs now rather than
# the handful of flat illustrations it was built for.
#
# (The single stylix wallpaper — `stylix.image` — is themed separately by
# _styling/wallpaper.nix, which uses gowall. That one drives colour *generation*;
# these are just pictures, so plain imagemagick is enough.)
#
# The directory is assembled with linkFarm rather than copied into $HOME, so the
# images stay in the store and cost nothing to "install". Drop your own files
# into `cosmos.desktops.wallpapers.directory` and they show up alongside these —
# the picker is pointed at that writable directory, with the defaults symlinked
# in on activation.
{...}: {
  # The collection itself, as a non-flake input so the revision is pinned in
  # flake.lock with everything else (and picked up by flake-bump) rather than
  # in a hash next to a `fetchgit` call.
  #
  # Fetched over the knot's *public HTTPS* rather than `git@knot.lvdar.nl:` on
  # purpose: this is built on voyager and, through build-gate, on endeavour, and
  # neither should need an SSH credential in order to produce a wallpaper. The
  # `did:plc:` path is the repo's persistent name — it survives a rename, where
  # `lvdar.nl/wallpapers` would not — and is the same shape comin uses to reach
  # nix-config (see services/comin.nix).
  #
  # `shallow=1` because this is ~20 MB of pictures and no history is wanted.
  #
  # Remember `nix run .#write-flake` after touching this.
  flake-file.inputs.wallpapers = {
    url = "git+https://knot.lvdar.nl/did:plc:nmkqw2d6qov4smqqvovwmwof?shallow=1";
    flake = false;
  };

  den.aspects.home.wallpapers.homeManager = {
    config,
    inputs,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) str path;

    cfg = config.cosmos.desktops.wallpapers;

    repo = inputs.wallpapers;

    # Which files in the repo are backgrounds, resolved by globbing it at BUILD
    # time rather than reading it during evaluation.
    #
    # `builtins.readDir` on a fetched store path would force the fetch at eval
    # (import-from-derivation), so every `nix flake check` — the servers
    # included, which have no desktop at all — would have to download the whole
    # picture collection to answer a question about something else.
    #
    # `stylix-source-logo.png` is excluded: it is in the repo because
    # _styling/wallpaper.nix derives the colour scheme from it, not because it
    # is a background to choose.
    imageList = pkgs.runCommand "wallpaper-list" {} ''
      shopt -s nullglob
      touch $out
      for _img in ${repo}/defaults/* ${repo}/frieren/*; do
        case "$(basename "$_img")" in
          stylix-source-logo.png) continue ;;
          *.jpg | *.jpeg | *.png) printf '%s\n' "$_img" >> $out ;;
        esac
      done
    '';

    # A 16x1 swatch strip of the base16 palette — imagemagick's `-remap` takes
    # its target colours from an image, not a list.
    palette = let
      colors = with config.lib.stylix.colors.withHashtag; [
        base00
        base01
        base02
        base03
        base04
        base05
        base06
        base07
        base08
        base09
        base0A
        base0B
        base0C
        base0D
        base0E
        base0F
      ];
    in
      pkgs.runCommand "base16-palette.png" {nativeBuildInputs = [pkgs.imagemagick];} ''
        magick ${lib.concatMapStringsSep " " (c: "'xc:${c}'") colors} +append png:$out
      '';

    # Dithering matters: a flat 16-colour remap posterises photographs into
    # banded blobs, Floyd–Steinberg keeps the gradients readable.
    #
    # Run in parallel: this is a hundred-odd images and it reruns in full
    # whenever the palette changes, which makes it comfortably the slowest step
    # of a rebuild if done one at a time.
    themed =
      pkgs.runCommand "wallpapers-themed" {nativeBuildInputs = [pkgs.imagemagick];}
      ''
        mkdir -p $out
        xargs -a ${imageList} -P "$NIX_BUILD_CORES" -I% \
          sh -c 'magick "$1" -dither FloydSteinberg -remap "$2" "$3/$(basename "$1")"' _ % ${palette} $out
      '';

    # Symlinks rather than copies — the originals are already in the store.
    plain = pkgs.runCommand "wallpapers-plain" {} ''
      mkdir -p $out
      while IFS= read -r _img; do
        ln -s "$_img" "$out/$(basename "$_img")"
      done < ${imageList}
    '';
  in {
    options.cosmos.desktops.wallpapers = {
      directory = mkOption {
        type = str;
        default = "${config.home.homeDirectory}/Pictures/wallpapers";
        description = ''
          Directory the wallpaper picker browses. Seeded with the default
          backgrounds; your own images can be added freely.
        '';
      };

      theme.enable =
        mkEnableOption "recolouring the bundled backgrounds to the stylix palette";

      defaultWallpaper = mkOption {
        type = str;
        default = "${cfg.directory}/birds-in-the-sky.jpg";
        description = ''
          Background used when the shell has no wallpaper picked yet. Must be a
          path inside `directory` so the picker shows it as selected.
        '';
      };

      defaults = mkOption {
        type = path;
        readOnly = true;
        default =
          if cfg.theme.enable
          then themed
          else plain;
        description = "Store directory holding the bundled default backgrounds.";
      };
    };

    config = {
      cosmos.system.impermanence.persist.directories = ["Pictures/wallpapers"];

      # Symlink the defaults into the (writable) picker directory. Existing
      # symlinks are re-pointed (the store path changes whenever the palette
      # does), dangling ones are pruned, and real files the user dropped in are
      # never touched.
      home.activation.defaultWallpapers = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p ${lib.escapeShellArg cfg.directory}
        for _wp in ${lib.escapeShellArg cfg.directory}/*; do
          if [ -L "$_wp" ] && [ ! -e "$_wp" ]; then run rm -- "$_wp"; fi
        done
        for _wp in ${cfg.defaults}/*; do
          _dest=${lib.escapeShellArg cfg.directory}/"$(basename "$_wp")"
          if [ ! -e "$_dest" ] || [ -L "$_dest" ]; then
            run ln -sfn "$_wp" "$_dest"
          fi
        done
      '';
    };
  };
}
