# home.yazi — yazi as a nix-wrapper-modules package (`nix run .#yazi`); the
# wrapper holds the theme (a port of stylix's yazi target), home-manager only
# installs it plus the `y` cd-on-exit function and the defaultApplication option.
{
  inputs,
  cosmosStyling,
  ...
}: let
  mkYazi = pkgs: let
    colors = cosmosStyling.colors pkgs;
    c = colors.withHashtag;
    mkFg = fg: {inherit fg;};
    mkBg = bg: {inherit bg;};
    mkBoth = fg: bg: {inherit fg bg;};
    mkSame = col: mkBoth col col;
    # Nerd Font codepoints, kept as escapes so the source stays readable.
    glyph = cp: builtins.fromJSON ''"\u${cp}"'';
    mkIcon = cp: fg: {
      text = glyph cp;
      inherit fg;
    };
  in
    inputs.nix-wrapper-modules.wrappers.yazi.wrap {
      inherit pkgs;

      settings.theme = {
        mgr = {
          syntect_theme = colors {
            # base16.nix treats a string `template` as template text, not a path.
            template = builtins.readFile "${inputs.stylix}/modules/bat/base16-stylix.tmTheme.mustache";
            extension = ".tmTheme";
          };

          cwd = mkFg c.cyan;
          find_keyword = mkFg c.green // {bold = true;};
          find_position = mkFg c.magenta;
          marker_selected = mkSame c.yellow;
          marker_copied = mkSame c.green;
          marker_cut = mkSame c.red;
          border_style = mkFg c.base04;

          count_copied = mkBoth c.base00 c.green;
          count_cut = mkBoth c.base00 c.red;
          count_selected = mkBoth c.base00 c.yellow;
        };

        indicator = rec {
          current = mkBg c.base02 // {bold = true;};
          preview = current;
        };

        tabs = {
          active = mkBoth c.base00 c.blue // {bold = true;};
          inactive = mkBoth c.blue c.base01;
        };

        mode = {
          normal_main = mkBoth c.base00 c.blue // {bold = true;};
          normal_alt = mkBoth c.blue c.base00;
          select_main = mkBoth c.base00 c.green // {bold = true;};
          select_alt = mkBoth c.green c.base00;
          unset_main = mkBoth c.base00 c.brown // {bold = true;};
          unset_alt = mkBoth c.brown c.base00;
        };

        status = {
          progress_label = mkBoth c.base05 c.base00;
          progress_normal = mkBoth c.base05 c.base00;
          progress_error = mkBoth c.red c.base00;
          perm_type = mkFg c.blue;
          perm_read = mkFg c.yellow;
          perm_write = mkFg c.red;
          perm_exec = mkFg c.green;
          perm_sep = mkFg c.cyan;
        };

        pick = {
          border = mkFg c.blue;
          active = mkFg c.magenta;
          inactive = mkFg c.base05;
        };

        input = {
          border = mkFg c.blue;
          title = mkFg c.base05;
          value = mkFg c.base05;
          selected = mkBg c.base03;
        };

        completion = {
          border = mkFg c.blue;
          active = mkBoth c.magenta c.base03;
          inactive = mkFg c.base05;
        };

        tasks = {
          border = mkFg c.blue;
          title = mkFg c.base05;
          hovered = mkBoth c.base05 c.base03;
        };

        which = {
          mask = mkBg c.base02;
          cand = mkFg c.cyan;
          rest = mkFg c.brown;
          desc = mkFg c.base05;
          separator_style = mkFg c.base04;
        };

        help = {
          on = mkFg c.magenta;
          run = mkFg c.cyan;
          desc = mkFg c.base05;
          hovered = mkBoth c.base05 c.base03;
          footer = mkFg c.base05;
        };

        filetype.rules = let
          mkRule = mime: fg: {inherit mime fg;};
        in [
          (mkRule "image/*" c.cyan)
          (mkRule "video/*" c.yellow)
          (mkRule "audio/*" c.yellow)

          (mkRule "application/zip" c.magenta)
          (mkRule "application/gzip" c.magenta)
          (mkRule "application/tar" c.magenta)
          (mkRule "application/bzip" c.magenta)
          (mkRule "application/bzip2" c.magenta)
          (mkRule "application/7z-compressed" c.magenta)
          (mkRule "application/rar" c.magenta)
          (mkRule "application/xz" c.magenta)

          (mkRule "application/doc" c.green)
          (mkRule "application/pdf" c.green)
          (mkRule "application/rtf" c.green)
          (mkRule "application/vnd.*" c.green)

          # A url rule: directory mime types are only resolved once hovered.
          {
            url = "*/";
            fg = c.blue;
            bold = true;
          }
          (mkRule "*" c.base05)
        ];

        icon = {
          dirs = let
            mkDirIcon = name: cp: fg: mkIcon cp fg // {inherit name;};
          in [
            (mkDirIcon ".config" "e5fc" c.orange)
            (mkDirIcon ".git" "e5fb" c.cyan)
            (mkDirIcon ".github" "e5fd" c.blue)
            (mkDirIcon ".npm" "e5fa" c.blue)
            (mkDirIcon "Desktop" "f108" c.cyan)
            (mkDirIcon "Development" "e70c" c.cyan)
            (mkDirIcon "Documents" "f401" c.cyan)
            (mkDirIcon "Downloads" "f498" c.cyan)
            (mkDirIcon "Library" "eb9c" c.cyan)
            (mkDirIcon "Movies" "f447" c.cyan)
            (mkDirIcon "Music" "f025" c.cyan)
            (mkDirIcon "Pictures" "e244" c.cyan)
            (mkDirIcon "Public" "f42b" c.cyan)
            (mkDirIcon "Videos" "f447" c.cyan)
          ];

          conds = let
            mkCondIcon = cond: cp: fg: mkIcon cp fg // {"if" = cond;};
          in [
            (mkCondIcon "orphan" "f127" c.base05)
            (mkCondIcon "link" "f481" c.base04)
            (mkCondIcon "block" "f0c9" c.yellow)
            (mkCondIcon "char" "f1c0" c.yellow)
            (mkCondIcon "fifo" "f1d1" c.yellow)
            (mkCondIcon "sock" "f1e4" c.yellow)
            (mkCondIcon "sticky" "f08d" c.yellow)
            (mkCondIcon "dummy" "f057" c.red)

            (mkCondIcon "dir" "e5ff" c.blue)
            (mkCondIcon "exec" "f489" c.green)
            (mkCondIcon "!dir" "f15b" c.base05)
          ];
        };
      };
    };
in {
  perSystem = {pkgs, ...}: {packages.yazi = mkYazi pkgs;};

  den.aspects.home.yazi.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.cosmos.cli.programs.yazi;
  in {
    options.cosmos.cli.programs.yazi.defaultApplication = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    config = {
      home.packages = [(mkYazi pkgs)];

      cosmos.cli.shells.zsh.initContent = ''
        function y() {
          local tmp="$(mktemp -t "yazi-cwd.XXXXX")"
          command yazi "$@" --cwd-file="$tmp"
          if cwd="$(<"$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
            builtin cd -- "$cwd"
          fi
          rm -f -- "$tmp"
        }
      '';

      xdg.mimeApps = lib.mkIf cfg.defaultApplication {
        enable = true;
        defaultApplications."inode/directory" = ["yazi.desktop"];
      };
    };
  };
}
