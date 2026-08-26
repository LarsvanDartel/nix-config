# home.wallpapers — the background collection, linked into a directory the
# wallpaper picker (noctalia's WallpaperSelector / control centre) browses.
#
# The images come from their own git repo on the knot (the `wallpapers` flake
# input, declared below) rather than being fetched one file at a time. They are
# binary, they change as a set, and the previous shape needed a URL and a hash
# per image — adding one meant editing nix, and there was nowhere to put a
# picture that was not also a nix expression.
#
# `ranking.txt` in that repo is the collection in preference order, best first,
# and it is what this file is built around: it decides which files are
# backgrounds at all, what order they appear in, and which one is the default.
# Re-rank, push, bump the input, and all three follow.
#
# `theme.enable` will run them through imagemagick's `-remap` against a swatch
# strip built from the 16 base16 colours, with Floyd-Steinberg dithering, so a
# background uses *only* theme colours. It is off: a sixteen-colour remap is a
# heavy hand on a photograph, and the collection is photographs now rather than
# the handful of flat illustrations it was built for.
#
# Images stay in the store and are symlinked into the picker directory, so they
# cost nothing to "install". Drop your own files in alongside them — the picker
# reads that writable directory, and activation only ever touches symlinks it
# put there itself.
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

    # `ranking.txt` is one filename per line and nothing else, which is the
    # whole reason it is a bare list: this reads it without parsing anything.
    #
    # `inputs.wallpapers` is a fetched source path rather than a derivation
    # output, so this is an ordinary file read during evaluation — not
    # import-from-derivation, and not a reason to build anything.
    ranking =
      lib.filter (l: l != "")
      (lib.splitString "\n" (builtins.readFile "${repo}/ranking.txt"));

    # Which subdirectory a name lives in is not knowable from the name alone,
    # and guessing wrong would produce a path that silently does not exist — so
    # look, and fail loudly at eval if it is in neither.
    resolve = name: let
      dir =
        lib.findFirst
        (d: builtins.pathExists "${repo}/${d}/${name}")
        null ["frieren" "defaults"];
    in
      assert lib.assertMsg (dir != null) ''
        cosmos.desktops.wallpapers: ranking.txt names "${name}", which is in
        neither frieren/ nor defaults/ of the wallpapers input.
      ''; "${repo}/${dir}/${name}";

    # Every background, in rank order, with its rank baked into the filename.
    #
    # The prefix is the point: the picker sorts by name and has no idea a
    # ranking exists, so numbering the files is what makes it list them best
    # first. It also gives the rotation below a trivial way to say "the top
    # eight" — `sort | head -8`.
    ordered =
      lib.imap1 (i: name: {
        inherit name;
        file = "${lib.fixedWidthNumber 3 i}-${name}";
        src = resolve name;
      })
      ranking;

    favourite = builtins.head ordered;

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

    # "<source> <destination name>" per line. Neither store paths nor these
    # filenames contain spaces, so a plain word split is enough.
    pairs =
      pkgs.writeText "wallpaper-pairs"
      (lib.concatMapStrings (w: "${w.src} ${w.file}\n") ordered);

    # Dithering matters: a flat 16-colour remap posterises photographs into
    # banded blobs, Floyd–Steinberg keeps the gradients readable.
    #
    # Run in parallel: this is ninety images and it reruns in full whenever the
    # palette changes, which would make it comfortably the slowest step of a
    # rebuild if done one at a time.
    themed =
      pkgs.runCommand "wallpapers-themed" {nativeBuildInputs = [pkgs.imagemagick];}
      ''
        mkdir -p $out
        export OUT=$out PALETTE=${palette}
        xargs -a ${pairs} -L1 -P "$NIX_BUILD_CORES" \
          sh -c 'magick "$1" -dither FloydSteinberg -remap "$PALETTE" "$OUT/$2"' _
      '';

    # Symlinks rather than copies — the originals are already in the store.
    plain = pkgs.runCommand "wallpapers-plain" {} ''
      mkdir -p $out
      export OUT=$out
      xargs -a ${pairs} -L1 sh -c 'ln -s "$1" "$OUT/$2"' _
    '';
  in {
    options.cosmos.desktops.wallpapers = {
      directory = mkOption {
        type = str;
        default = "${config.home.homeDirectory}/Pictures/wallpapers";
        description = ''
          Directory the wallpaper picker browses. Seeded with the ranked
          collection; your own images can be added freely.
        '';
      };

      theme.enable =
        mkEnableOption "recolouring the bundled backgrounds to the stylix palette";

      defaultWallpaper = mkOption {
        type = str;
        default = "${cfg.directory}/${favourite.file}";
        description = ''
          Background used when the shell has no wallpaper picked yet. Must be a
          path inside `directory` so the picker shows it as selected.

          Defaults to the top of the ranking, so re-ranking the collection and
          pushing it is enough to change what a fresh shell comes up with.
        '';
      };

      favourite = mkOption {
        type = str;
        readOnly = true;
        default = favourite.src;
        description = ''
          Store path of the top-ranked background. home.styling points
          `stylix.image` at this, which is what hyprpaper, hyprlock and the
          greeter display.
        '';
      };

      defaults = mkOption {
        type = path;
        readOnly = true;
        default =
          if cfg.theme.enable
          then themed
          else plain;
        description = "Store directory holding the ranked backgrounds.";
      };
    };

    config = {
      cosmos.system.impermanence.persist.directories = ["Pictures/wallpapers"];

      # Symlink the collection into the (writable) picker directory.
      #
      # The pruning pass is not optional bookkeeping: filenames carry the rank,
      # so they change whenever the ranking does, and an image dropped from the
      # collection would otherwise stay in the picker forever. Testing for a
      # *dangling* link is not enough either — the superseded store path is
      # still there until it is garbage collected, so the stale link resolves
      # perfectly well. Hence: remove any symlink pointing into the store that
      # is not part of the current set, and never touch a real file.
      home.activation.defaultWallpapers = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p ${lib.escapeShellArg cfg.directory}

        for _wp in ${lib.escapeShellArg cfg.directory}/*; do
          [ -L "$_wp" ] || continue
          case "$(readlink -- "$_wp")" in
            /nix/store/*) ;;
            *) continue ;;
          esac
          if [ ! -e ${cfg.defaults}/"$(basename "$_wp")" ]; then
            run rm -- "$_wp"
          fi
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
