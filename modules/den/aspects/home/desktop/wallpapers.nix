# home.wallpapers — the background collection, symlinked into the directory
# the picker (noctalia's WallpaperSelector / control centre) browses. Images
# live in their own git repo (the `wallpapers` flake input below): binaries
# that change as a set. ranking.txt there is the preference order and drives
# everything — what counts as a background, picker order, the default, the
# rotation; re-rank, push, bump the input. theme.enable (base16 remap via
# imagemagick) is off: the collection is photographs now, and a sixteen-colour
# remap is too heavy a hand. Store files are only symlinked; the picker
# directory stays writable for your own images.
{...}: {
  # Non-flake input so the revision pins in flake.lock (and flake-bump picks
  # it up). Public HTTPS, not git@knot: built on voyager and endeavour via
  # build-gate, neither of which should need an SSH credential for a
  # wallpaper. `did:plc:` is the repo's persistent name (survives a rename;
  # same shape comin uses, see services/comin.nix). shallow=1: ~20 MB of
  # pictures, no history wanted. Remember `nix run .#write-flake` after this.
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
    inherit (lib.types) str path ints;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.desktops.wallpapers;

    repo = inputs.wallpapers;

    # ranking.txt is one filename per line; the input is a fetched source
    # path, so this is an ordinary eval-time file read, not IFD.
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

    # Rank-prefixed filenames: the picker sorts by name and knows nothing of
    # the ranking, so numbering is what lists them best first (and gives the
    # rotation its "top eight" via `sort | head -8`).
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

    # Floyd–Steinberg: a flat 16-colour remap posterises photographs into
    # banded blobs. Parallel because this is ninety images, rerun in full
    # whenever the palette changes.
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

    # Cycles the top of the ranking — not noctalia's own automation (whole-
    # directory shuffle, niri-only); this drives whichever shell is up. Index
    # in XDG_RUNTIME_DIR: a reboot restarts from the favourite, so there is
    # no state to persist.
    rotate = pkgs.writeShellScript "wallpaper-rotate" ''
      set -eu
      dir=${lib.escapeShellArg cfg.directory}
      n=${toString cfg.rotate.count}
      state="''${XDG_RUNTIME_DIR:-/tmp}/wallpaper-rotate.index"

      i=0
      if [ -r "$state" ]; then i=$(cat "$state" 2>/dev/null || echo 0); fi
      case "$i" in ''' | *[!0-9]*) i=0 ;; esac
      i=$(( (i + 1) % n ))
      printf '%s\n' "$i" > "$state"

      # Filenames are rank-prefixed, so sorting by name sorts by rank.
      pick=$(ls -1 "$dir" 2>/dev/null | sort | head -n "$n" | sed -n "$((i + 1))p")
      [ -n "$pick" ] || exit 0
      path="$dir/$pick"
      [ -e "$path" ] || exit 0

      # noctalia owns the background under niri; hyprpaper under Hyprland.
      # Whichever is not running simply fails, so try one and fall back.
      #
      # Failing loudly matters here. An earlier version swallowed both attempts
      # and exited 0, so a unit that could not find either binary still looked
      # perfectly healthy in `systemctl --user status` and left nothing in the
      # journal to explain a background that never changed.
      if command -v noctalia-shell >/dev/null 2>&1 &&
         noctalia-shell ipc call wallpaper set "$path" all >/dev/null 2>&1; then
        echo "set $pick via noctalia"
        exit 0
      fi
      if command -v hyprctl >/dev/null 2>&1 &&
         hyprctl hyprpaper reload ",$path" >/dev/null 2>&1; then
        echo "set $pick via hyprpaper"
        exit 0
      fi
      echo "could not set $pick: no running shell accepted it" >&2
      exit 1
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

      rotate = {
        enable =
          mkEnableOption ''
            cycling the background through the best-ranked images on a timer
          ''
          // {default = true;};

        count = mkOption {
          type = ints.positive;
          default = 8;
          description = ''
            How many of the top-ranked backgrounds to cycle through. Kept well
            below the size of the collection on purpose — the point of ranking
            it was to stop seeing the ones that lost.
          '';
        };

        interval = mkOption {
          type = str;
          default = "30min";
          description = "systemd time span between changes.";
        };
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

      # Pruning is not optional bookkeeping: rank-prefixed names change with
      # the ranking, so a dropped image would linger in the picker forever.
      # Dangling-link tests don't cut it — the superseded store path resolves
      # fine until GC — so remove any store-pointing symlink not in the
      # current set, and never touch a real file.
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

      systemd.user = mkIf cfg.rotate.enable {
        services.wallpaper-rotate = {
          Unit = {
            Description = "Advance the background to the next of the top ${toString cfg.rotate.count}";
            PartOf = ["graphical-session.target"];
            After = ["graphical-session.target"];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${rotate}";
            # User-manager PATH is not the session's: coreutils for the
            # script, /run/current-system/sw/bin for hyprctl, profile for
            # noctalia-shell. `home.profileDirectory`, not a literal — this
            # profile is ~/.local/state/nix/profile and ~/.nix-profile does
            # not exist here, which once left the rotation silently dead.
            Environment = [
              "PATH=${lib.makeBinPath [pkgs.coreutils]}:/run/current-system/sw/bin:${config.home.profileDirectory}/bin"
            ];
          };
        };

        timers.wallpaper-rotate = {
          Unit = {
            Description = "Cycle the background through the top ${toString cfg.rotate.count}";
            PartOf = ["graphical-session.target"];
          };
          Timer = {
            # First tick a minute after the session, not `interval`: a fresh
            # session otherwise sits on one image for half an hour, which
            # looks exactly like a broken rotation.
            OnActiveSec = "1min";
            OnUnitActiveSec = cfg.rotate.interval;
          };
          Install.WantedBy = ["graphical-session.target"];
        };
      };
    };
  };
}
